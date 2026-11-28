import XCTest
@testable import SiteForge

final class CanvasRendererTests: XCTestCase {
    // SF-LOCAL-BUILDER-016 / SF-1211-004, SF-1204-004.
    @MainActor
    func testBrowserRetainedArtifactCannotOpenOrExportAfterImmediateProjectReplacement() async throws {
        let owned = try ApplicationOwnedTestFixture.create("preview-project-ownership")
        defer { try? owned.cleanup() }
        let document = ProjectCreation.blank()
        var liveDocumentID = document.id, opened = 0
        let controller = BrowserPreviewController { _ in opened += 1; return .opened }
        defer { controller.stop() }
        await controller.build(document: document, pageID: document.pages[0].id, package: .init(document: document),
            isDocumentCurrent: { $0 == liveDocumentID }, isCurrent: { _, _ in true }).value
        let original = try XCTUnwrap(controller.makeExportRequest())
        let plan = try XCTUnwrap(controller.plan)
        let deadline = ContinuousClock.now + .seconds(2)
        while controller.isOpeningBrowser, ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertFalse(controller.isOpeningBrowser)
        let priorOpens = opened
        // Simulate the actual event-turn gap before deferred noteRevision.
        liveDocumentID = DocumentID()
        XCTAssertEqual(controller.plan, plan, "The old immutable artifact is retained until ordinary invalidation")
        XCTAssertNil(controller.makeExportRequest())
        XCTAssertNil(controller.export(to: owned.url.appendingPathComponent("wrong-project"), request: original))
        controller.openAgain()
        XCTAssertFalse(controller.isOpeningBrowser); XCTAssertEqual(opened, priorOpens)
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.url.appendingPathComponent("wrong-project").path))
        controller.noteRevision(documentID: liveDocumentID, revision: 0)
        XCTAssertNil(controller.plan); XCTAssertNil(controller.findingReceipt)
    }

    // SF-LOCAL-BUILDER-015 / SF-1211-004/006.
    @MainActor
    func testBrowserFindingReceiptIsIndependentOfRetainedSuccessfulArtifactAndExportIntent() async throws {
        let owned = try ApplicationOwnedTestFixture.create("finding-receipt-export")
        defer { try? owned.cleanup() }
        let document = ProjectCreation.blank()
        let controller = BrowserPreviewController { _ in .opened }
        defer { controller.stop() }
        await controller.build(document: document, pageID: document.pages[0].id,
            package: .init(document: document), isCurrent: { _, _ in true }).value
        let success = try XCTUnwrap(controller.findingReceipt)
        let plan = try XCTUnwrap(controller.plan), url = try XCTUnwrap(controller.url)
        let oldExport = try XCTUnwrap(controller.makeExportRequest())
        XCTAssertTrue(controller.ownsCurrentFindings(success))
        // Same canonical revision, different failed attempt: revision equality
        // alone cannot identify either the findings or the successful artifact.
        await controller.build(document: document, pageID: document.pages[0].id,
            package: .init(document: ProjectCreation.blank()), isCurrent: { _, _ in true }).value
        let failure = try XCTUnwrap(controller.findingReceipt)
        XCTAssertNotEqual(failure.id, success.id); XCTAssertEqual(failure.revision, success.revision)
        XCTAssertTrue(failure.findings.contains { $0.code == "resource-snapshot-invalid" })
        XCTAssertEqual(controller.plan, plan); XCTAssertEqual(controller.url, url)
        XCTAssertEqual(controller.revision, document.revision); XCTAssertEqual(controller.documentID, document.id)
        XCTAssertFalse(controller.ownsCurrentFindings(success)); XCTAssertTrue(controller.ownsCurrentFindings(failure))
        XCTAssertTrue(controller.artifactSummary.contains("Last successful website"))
        XCTAssertTrue(controller.artifactSummary.contains("later attempt"))
        XCTAssertTrue(controller.status.contains("Refresh")); XCTAssertFalse(controller.status.contains("Retry"))
        let destination = owned.url.appendingPathComponent("old-intent")
        XCTAssertNil(controller.export(to: destination, request: oldExport))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let retainedExport = try XCTUnwrap(controller.makeExportRequest())
        XCTAssertEqual(retainedExport.plan, plan, "Only the explicit retained successful snapshot may export")
        let cancelled = try XCTUnwrap(controller.export(to: owned.url.appendingPathComponent("cancelled"), request: retainedExport))
        XCTAssertTrue(controller.isExporting); XCTAssertFalse(controller.ownsCurrentFindings(failure))
        XCTAssertNil(controller.makeExportRequest())
        controller.cancelExport(); await cancelled.value
        XCTAssertEqual(controller.plan, plan); XCTAssertEqual(controller.url, url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.url.appendingPathComponent("cancelled").path))
        controller.cancel()
        XCTAssertFalse(controller.ownsFindingAttempt(failure)); XCTAssertEqual(controller.plan, plan)
        controller.noteRevision(documentID: DocumentID(), revision: 0)
        XCTAssertNil(controller.findingReceipt); XCTAssertNil(controller.plan); XCTAssertNil(controller.url)
    }

    // SF-1203-004/1211-004: cancellation before promotion preserves an
    // existing destination byte-for-byte and removes only our private stage.
    func testStaticWriterLiveCancellationBeforePromotionPreservesExistingOutput() async throws {
        let fixture = try ApplicationOwnedTestFixture.create("export-cancellation")
        defer { try? fixture.cleanup() }
        let destination = fixture.url.appendingPathComponent("website")
        let old = LocalStaticBuildPlan(revision: 1, files: [.init(path: "index.html", contents: "old")])
        try LocalStaticBuildWriter.write(old, to: destination, expectedRevision: 1)
        let next = LocalStaticBuildPlan(revision: 2, files: [.init(path: "index.html", contents: "new")])
        let barrier = DeterministicCancellationBarrier(blockAt: 3)
        let task = Task.detached {
            try LocalStaticBuildWriter.write(next, to: destination, expectedRevision: 2, replacingExisting: true,
                cancellation: .init(barrier.check))
        }
        await barrier.waitUntilBlocked()
        task.cancel(); barrier.release()
        do { try await task.value; XCTFail("Cancelled staging must not promote") }
        catch { XCTAssertEqual(error as? LocalStaticBuildWriteError, .cancelled) }
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("index.html"), encoding: .utf8), "old")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.url.path), ["website"])
    }

    @MainActor func testBrowserExportPanelIntentCannotRetargetReplacementBuild() async throws {
        let fixture = try ApplicationOwnedTestFixture.create("export-intent")
        defer { try? fixture.cleanup() }
        let session = DocumentSession(document: ProjectCreation.blank())
        let controller = BrowserPreviewController { _ in .opened }
        defer { controller.stop() }
        await controller.build(document: session.document, pageID: session.document.pages[0].id,
            package: .init(document: session.document), isCurrent: { _, _ in true }).value
        let captured = try XCTUnwrap(controller.makeExportRequest())
        try session.execute(.renamePage(.init(pageID: session.document.pages[0].id, name: "Changed")))
        await controller.build(document: session.document, pageID: session.document.pages[0].id,
            package: .init(document: session.document), isCurrent: { _, _ in true }).value
        let staleDestination = fixture.url.appendingPathComponent("stale")
        XCTAssertNil(controller.export(to: staleDestination, request: captured))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleDestination.path))
        let current = try XCTUnwrap(controller.makeExportRequest())
        let destination = fixture.url.appendingPathComponent("current")
        let write = try XCTUnwrap(controller.export(to: destination, request: current))
        await write.value
        XCTAssertNil(controller.exportFailure, controller.status)
        for file in current.plan.files {
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(file.path)), Data(file.contents.utf8))
        }
        XCTAssertEqual(current.plan.revision, session.document.revision)
    }

    func testPackageBackedCompilerRejectsForeignSnapshotWithoutLeakingContent() {
        let document = ProjectCreation.blank(), foreign = ProjectCreation.blank()
        let result = StaticBuildCompiler.compile(document: document,
            profileSelection: .init(profile: .development), package: .init(document: foreign))
        XCTAssertFalse(result.canWrite); XCTAssertNil(result.plan)
        XCTAssertEqual(result.findings.map(\.code), ["resource-snapshot-invalid"])
        XCTAssertFalse(result.redactedSummary.contains(foreign.id.description))
        XCTAssertFalse(result.redactedSummary.contains(document.id.description))
    }
    @MainActor func testBrowserPreviewPendingIdentityCancelsReplacementAndRevisionWithoutOpeningBrowser() async throws {
        let document = ProjectCreation.blank()
        var opened = 0
        let controller = BrowserPreviewController { _ in opened += 1; return .opened }
        let first = controller.build(document: document, pageID: document.pages[0].id,
            package: .init(document: document), isCurrent: { _, _ in true })
        controller.noteRevision(documentID: DocumentID(), revision: 0)
        XCTAssertFalse(controller.isBuilding)
        await first.value
        XCTAssertNil(controller.plan); XCTAssertNil(controller.url); XCTAssertEqual(opened, 0)
        XCTAssertEqual(controller.status, "Website preview stopped.")
        let second = controller.build(document: document, pageID: document.pages[0].id,
            package: .init(document: document), isCurrent: { _, _ in true })
        controller.noteRevision(documentID: document.id, revision: document.revision + 1)
        XCTAssertFalse(controller.isBuilding)
        await second.value
        XCTAssertEqual(opened, 0); XCTAssertNil(controller.plan)
        XCTAssertTrue(controller.status.contains("Refresh"))
        let third = controller.build(document: document, pageID: document.pages[0].id,
            package: .init(document: document), isCurrent: { _, _ in false })
        await third.value
        XCTAssertFalse(controller.isBuilding); XCTAssertNil(controller.plan)
        XCTAssertEqual(opened, 0)
        controller.stop()
    }

    @MainActor func testBrowserPreviewExportUsesExactSnapshotAndSupersededCompletionKeepsStoppedStatus() async throws {
        let fixture = try ApplicationOwnedTestFixture.create("preview-boundary")
        defer { try? fixture.cleanup() }
        let document = ProjectCreation.blank()
        let controller = BrowserPreviewController { _ in .opened }
        let build = controller.build(document: document, pageID: document.pages[0].id,
            package: .init(document: document), isCurrent: { _, _ in true })
        await build.value
        let plan = try XCTUnwrap(controller.plan)
        let destination = fixture.url.appendingPathComponent("website")
        let export = try XCTUnwrap(controller.export(to: destination))
        await export.value
        XCTAssertFalse(controller.isExporting)
        XCTAssertNil(controller.exportFailure, controller.status)
        for file in plan.files {
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(file.path)), Data(file.contents.utf8))
        }
        XCTAssertTrue(controller.status.contains("Exported"))
        let second = fixture.url.appendingPathComponent("second-website")
        let cancelled = try XCTUnwrap(controller.export(to: second))
        controller.stop()
        await cancelled.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
        XCTAssertEqual(controller.status, "Website preview stopped.")
        XCTAssertFalse(controller.isExporting)
        let unsafe = LocalStaticBuildPlan(revision: plan.revision, files: [.init(path: "../escape.html", contents: "not allowed")])
        XCTAssertThrowsError(try LocalStaticBuildWriter.write(unsafe, to: fixture.url.appendingPathComponent("unsafe"), expectedRevision: plan.revision)) {
            XCTAssertEqual($0 as? LocalStaticBuildWriteError, .unsafeDestination)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url.appendingPathComponent("escape.html").path))
    }

    @MainActor func testBrowserPreviewLateOpenCompletionCannotReplaceStoppedFeedback() async throws {
        let document = ProjectCreation.blank()
        var continuation: CheckedContinuation<BrowserPreviewController.BrowserOpenResult, Never>?
        let completed = expectation(description: "Native browser-open adapter returned")
        let controller = BrowserPreviewController { _ in
            let result = await withCheckedContinuation { continuation = $0 }
            completed.fulfill()
            return result
        }
        let build = controller.build(document: document, pageID: document.pages[0].id,
            package: .init(document: document), isCurrent: { _, _ in true })
        await build.value
        let deadline = ContinuousClock.now + .seconds(3)
        while continuation == nil, ContinuousClock.now < deadline { await Task.yield() }
        let pending = try XCTUnwrap(continuation)
        controller.stop(); pending.resume(returning: .failed)
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(controller.status, "Website preview stopped.")
        XCTAssertNil(controller.url); XCTAssertNil(controller.plan)
    }
    // SF-1201-003/004, SF-1206-003/004: serve the immutable export artifact,
    // never client-supplied filesystem paths or a DNS-rebound Host.
    func testBrowserPreviewHTTPRoutesExactExportBytesAndHead() throws {
        let image = Data([0, 1, 254, 255])
        let plan = LocalStaticBuildPlan(revision: 9, files: [
            .init(path: "index.html", contents: "<h1>Home</h1>"),
            .init(path: "contact.html", contents: "Contact"),
            .init(path: "404.html", contents: "Missing")
        ], binaryFiles: [.init(path: "assets/photo.png", contents: image)])
        let content = try WebsitePreviewHTTPContent(plan: plan)
        func request(_ path: String, method: String = "GET") -> WebsitePreviewHTTPContent.Response {
            content.response(to: Data("\(method) \(path) HTTP/1.1\r\nHost: 127.0.0.1:4321\r\n\r\n".utf8), port: 4321)
        }
        XCTAssertEqual(request("/").body, Data(plan.files[0].contents.utf8))
        XCTAssertEqual(request("/contact?query=hello").body, Data("Contact".utf8))
        XCTAssertEqual(request("/assets/photo.png").body, image)
        XCTAssertEqual(request("/assets/photo.png").type, "image/png")
        XCTAssertEqual(request("/missing").status, 404)
        XCTAssertEqual(request("/missing").body, Data("Missing".utf8))
        let head = request("/", method: "HEAD")
        XCTAssertTrue(head.headOnly)
        XCTAssertTrue(String(decoding: head.bytes, as: UTF8.self).hasSuffix("\r\n\r\n"))
        XCTAssertTrue(String(decoding: head.bytes, as: UTF8.self).contains("Content-Length: \(head.body.count)"))
        XCTAssertEqual(plan.revision, 9)
    }

    // SF-1202-003/004, SF-1206-003/004: a valid named page needs no synthetic
    // home document. HTTP preserves exact compiler bytes and missing-root truth.
    func testBrowserPreviewNamedPageWithoutHomePreservesExactRouteAndBytes() throws {
        let page = "<h1>Named page</h1>"
        let plan = LocalStaticBuildPlan(revision: 13, files: [
            .init(path: "legacy-surface.html", contents: page),
            .init(path: "styles.css", contents: "h1 { color: black }")
        ])
        let content = try WebsitePreviewHTTPContent(plan: plan)
        for path in ["/legacy-surface", "/legacy-surface.html"] {
            let response = content.response(to: Data("GET \(path) HTTP/1.1\r\nHost: 127.0.0.1:4321\r\n\r\n".utf8), port: 4321)
            XCTAssertEqual(response.status, 200)
            XCTAssertEqual(response.type, "text/html; charset=utf-8")
            XCTAssertEqual(response.body, Data(page.utf8))
        }
        XCTAssertNil(content.files["index.html"])
        XCTAssertEqual(content.response(to: Data("GET / HTTP/1.1\r\nHost: 127.0.0.1:4321\r\n\r\n".utf8), port: 4321).status, 404)
        XCTAssertEqual(content.files.count, plan.files.count)
        XCTAssertThrowsError(try WebsitePreviewHTTPContent(plan: .init(revision: 13,
            files: [.init(path: "styles.css", contents: "safe")],
            binaryFiles: [.init(path: "fake.html", contents: Data([0]))])))
    }

    func testBrowserPreviewHTTPRejectsTraversalRebindingAndInvalidArtifacts() throws {
        let content = try WebsitePreviewHTTPContent(plan: .init(revision: 1, files: [.init(path: "index.html", contents: "safe")]))
        for path in ["/../private", "/%2e%2e/private", "/%252e%252e/private", "/a\\b", "/%00", "//external.test/", "http://external.test/"] {
            let response = content.response(to: Data("GET \(path) HTTP/1.1\r\nHost: 127.0.0.1:4321\r\n\r\n".utf8), port: 4321)
            XCTAssertEqual(response.status, 400, path)
        }
        for host in ["external.test:4321", "127.0.0.1:4322", "127.0.0.1:4321\r\nHost: localhost:4321"] {
            XCTAssertEqual(content.response(to: Data("GET / HTTP/1.1\r\nHost: \(host)\r\n\r\n".utf8), port: 4321).status, 400)
        }
        XCTAssertEqual(content.response(to: Data(repeating: 65, count: 16_385), port: 4321).status, 431)
        XCTAssertEqual(content.response(to: Data("POST / HTTP/1.1\r\nHost: localhost:4321\r\n\r\n".utf8), port: 4321).status, 405)
        for files: [LocalStaticBuildPlan.File] in [[], [.init(path: "../index.html", contents: "bad")], [.init(path: "index.html", contents: "a"), .init(path: "index.html", contents: "b")]] {
            XCTAssertThrowsError(try WebsitePreviewHTTPContent(plan: .init(revision: 1, files: files)))
        }
    }

    func testBrowserPreviewLoopbackServesImmutablePlanAndStops() async throws {
        let server = LoopbackWebsiteServer()
        let plan = LocalStaticBuildPlan(revision: 4, files: [.init(path: "index.html", contents: "<p>Exact authored output</p>")])
        let url = try await server.start(plan: plan)
        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertNotNil(url.port)
        let session = URLSession(configuration: .ephemeral)
        do {
            let (bytes, response) = try await session.data(from: url)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            XCTAssertEqual(bytes, Data(plan.files[0].contents.utf8))
            await server.stop()
            var request = URLRequest(url: url)
            request.timeoutInterval = 2
            do {
                _ = try await session.data(for: request)
                XCTFail("Stopped preview must not keep serving")
            } catch { /* Connection refusal is the expected teardown boundary. */ }
        } catch {
            await server.stop()
            session.invalidateAndCancel()
            throw error
        }
        session.invalidateAndCancel()
    }

    func testBrowserPreviewStoppedServerCannotRestart() async throws {
        let server = LoopbackWebsiteServer()
        await server.stop()
        do {
            _ = try await server.start(plan: .init(revision: 1, files: [.init(path: "index.html", contents: "safe")]))
            XCTFail("A retired scene server cannot restart")
        } catch { XCTAssertEqual(error as? WebsitePreviewError, .cancelled) }
    }

    func testBrowserPreviewWorkerWritesSameCompilerArtifactInsidePrivateOwnership() async throws {
        let document = ProjectCreation.blank()
        let worker = BrowserWebsiteBuilder()
        let (compilation, root) = try await worker.prepare(document: document, package: ProjectPackage(document: document))
        let owned = try XCTUnwrap(root)
        do {
            let permissions = try FileManager.default.attributesOfItem(atPath: owned.path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(permissions?.intValue, 0o700)
            let plan = try XCTUnwrap(compilation.plan)
            XCTAssertEqual(plan.revision, document.revision)
            let http = try WebsitePreviewHTTPContent(plan: plan)
            for file in plan.files {
                let written = try Data(contentsOf: owned.appendingPathComponent("website").appendingPathComponent(file.path))
                XCTAssertEqual(written, Data(file.contents.utf8))
                XCTAssertEqual(http.files[file.path], written)
            }
            await worker.removeOwnedOutput(owned)
            XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
        } catch {
            await worker.removeOwnedOutput(owned)
            throw error
        }
    }

    // SF-0202-003, SF-0303-003, SF-1102-003 — static navigation retains
    // canonical order, omits non-public roles, and reports the current page.
    func testStaticNavigationProjectionPreservesPageOrderAndAccessibleCurrentState() {
        let home = DocumentPage(name: "Home", route: .init(rawValue: "/"), role: .home)
        let standard = DocumentPage(name: "Guides & Help", route: .init(rawValue: "/guides"), role: .standard)
        let notFound = DocumentPage(name: "Not Found", route: .init(rawValue: "/404"), role: .notFound)
        let component = DocumentPage(name: "Card", route: .init(rawValue: ""), role: .componentDefinition)
        let entries = StaticNavigationEmitter.entries(
            pages: [home, standard, notFound, component],
            staticRoutes: [home.id: "index.html", standard.id: "guides.html", notFound.id: "404.html"],
            currentPageID: standard.id,
            currentOutputPath: "guides.html"
        )

        XCTAssertEqual(entries.map(\.pageID), [home.id, standard.id])
        XCTAssertEqual(entries.map(\.route), [home.route, standard.route])
        XCTAssertEqual(entries.map(\.isCurrent), [false, true])
        let output = StaticNavigationEmitter.emit(entries)
        XCTAssertTrue(output.hasPrefix("<nav aria-label=\"Site\"><ul>"))
        XCTAssertTrue(output.contains("href=\"index.html\">Home</a>"))
        XCTAssertTrue(output.contains("href=\"guides.html\" aria-current=\"page\">Guides &amp; Help</a>"))
        XCTAssertFalse(output.contains("404.html") || output.contains("Card"))

        let nested = DocumentPage(name: "Install", route: .init(rawValue: "/guides/install"), role: .standard)
        let nestedEntries = StaticNavigationEmitter.entries(
            pages: [home, nested],
            staticRoutes: [home.id: "index.html", nested.id: "guides/install.html"],
            currentPageID: nested.id,
            currentOutputPath: "guides/install.html"
        )
        XCTAssertEqual(nestedEntries.map(\.href), ["../index.html", "install.html"])
    }

    // SF-0806-003, SF-1102-003, SF-1203-003 — static output accepts only a
    // typed route projection. This remains independent of browser runtime.
    func testStaticControlCompilerEscapesTypedRoutesAndKeepsMissingTargetsInert() throws {
        let pageID = PageID()
        let rootID = NodeID(), sectionID = NodeID(), sectionLinkID = NodeID()
        let externalLinkID = NodeID(), missingLinkID = NodeID(), buttonID = NodeID()
        let root = DocumentNode(id: rootID, kind: .frame, name: "Root", parent: .page(pageID),
                                childIDs: [sectionID, sectionLinkID, externalLinkID, missingLinkID, buttonID])
        let section = DocumentNode(id: sectionID, kind: .section, name: "Destination", parent: .node(rootID))
        let sectionLink = DocumentNode(
            id: sectionLinkID, kind: .link, name: "Section link", parent: .node(rootID),
            properties: typedControlProperties(
                .section(pageID: pageID, nodeID: sectionID), label: "Jump <there>"
            )
        )
        let externalLink = DocumentNode(
            id: externalLinkID, kind: .link, name: "External link", parent: .node(rootID),
            properties: typedControlProperties(
                .external("https://example.com/a?b=1&c=2"), label: "External", context: .new
            )
        )
        let missingLink = DocumentNode(
            id: missingLinkID, kind: .link, name: "Missing link", parent: .node(rootID),
            properties: typedControlProperties(.page(PageID()), label: "Missing"
            )
        )
        let button = DocumentNode(id: buttonID, kind: .button, name: "Button", parent: .node(rootID))
        let page = DocumentPage(
            id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home,
            rootNodeIDs: [rootID], nodes: [root, section, sectionLink, externalLink, missingLink, button]
        )

        let tree = try InternalDocumentRenderTreeCompiler.compile(
            page: page, documentID: DocumentID(), revision: 1,
            staticRoutes: [pageID: "index.html"], sectionIDs: [pageID: [sectionID]]
        )
        let output = try SafeHTMLEmitter.emit(tree)
        let sectionAnchor = "sf-node-\(sectionID.rawValue.uuidString.lowercased())"
        XCTAssertTrue(output.contains("id=\"\(sectionAnchor)\""))
        XCTAssertTrue(output.contains("href=\"index.html#\(sectionAnchor)\">Jump &lt;there&gt;</a>"))
        XCTAssertTrue(output.contains("href=\"https://example.com/a?b=1&amp;c=2\" target=\"_blank\" rel=\"noopener noreferrer\">External</a>"))
        XCTAssertTrue(output.contains("role=\"link\" aria-disabled=\"true\">Missing</a>"))
        XCTAssertTrue(output.contains("<button") && output.contains("type=\"button\" disabled aria-disabled=\"true\">Button</button>"))
        XCTAssertFalse(output.contains("onclick=") || output.contains("<script"))
    }

    func testSafeHTMLEmitterEmitsAccessibleTextField() throws {
        let formID = NodeID()
        let id = NodeID()
        let nodes = [
            formNode(formID),
            InternalRenderTreeNode(id: id, sourceNodeID: id, paintOrder: 1, frame: Self.frame, semanticElement: "p", cssSelector: "", formField: .init(kind: "email", label: "Email", name: "email", help: nil, required: true, formID: formID, options: [], maximumLength: 128)),
        ]
        let output = try SafeHTMLEmitter.emit(.init(documentID: DocumentID(), revision: 1, nodes: nodes))
        XCTAssertTrue(output.contains("<label for=\"sf-field-"))
        XCTAssertTrue(output.contains("name=\"email\" type=\"email\" required"))
        XCTAssertTrue(output.contains("maxlength=\"128\""))
    }

    // SF-0506-003/005, SF-1203-003/004: typed navigation is shared by
    // styled Buttons and Links; no unconfigured action is made executable.
    func testTargetedButtonOutputRetainsSafeNavigationAndAuthoredBorder() throws {
        let pageID = PageID(), targetID = PageID(), id = NodeID(), missingID = NodeID()
        let prefix = DesignBoxStyleCommandRegistry.namespace
        var button = DocumentNode(id: id, kind: .button, name: "Read journal", parent: .page(pageID),
            properties: typedControlProperties(.page(targetID), label: "Read & explore", context: .new))
        button.properties += [
            .init(key: .init(rawValue: prefix + "border.width"), value: .number(1), origin: .authored),
            .init(key: .init(rawValue: prefix + "border.style"), value: .string("solid"), origin: .authored),
            .init(key: .init(rawValue: prefix + "border.color.red"), value: .number(0.4), origin: .authored),
            .init(key: .init(rawValue: prefix + "border.color.green"), value: .number(0.2), origin: .authored),
            .init(key: .init(rawValue: prefix + "border.color.blue"), value: .number(0.8), origin: .authored),
            .init(key: .init(rawValue: prefix + "border.color.alpha"), value: .number(1), origin: .authored),
        ]
        let missing = DocumentNode(id: missingID, kind: .button, name: "Missing", parent: .page(pageID),
            properties: typedControlProperties(.page(PageID()), label: "Missing"))
        let page = DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home,
            rootNodeIDs: [id, missingID], nodes: [button, missing])
        let tree = try InternalDocumentRenderTreeCompiler.compile(page: page, documentID: DocumentID(), revision: 1,
            staticRoutes: [pageID: "index.html", targetID: "journal.html"])
        let html = try SafeHTMLEmitter.emit(tree)
        XCTAssertTrue(html.contains("href=\"journal.html\" target=\"_blank\" rel=\"noopener noreferrer\">Read &amp; explore</a>"))
        XCTAssertTrue(html.contains("role=\"link\" aria-disabled=\"true\">Missing</a>"))
        XCTAssertEqual(tree.nodes.first(where: { $0.id == id })?.boxStyle?.border?.width, 1)
        XCTAssertTrue(StaticBoxStyleOutputEmitter.emit(nodes: tree.nodes).contains("rgba(102.0, 51.0, 204.0, 1.0)"))
        let css = StaticTypographyOutputEmitter.emit(nodes: tree.nodes)
        XCTAssertTrue(css.contains(":is(a,button) { display:flex;align-items:center;"))
        XCTAssertFalse(html.contains("onclick=") || html.contains("<script"))
    }

    func testSafeHTMLEmitterSafelyEmitsCheckboxSelectAndUnconfiguredSubmit() throws {
        let formID = NodeID()
        let selectID = NodeID()
        let checkboxID = NodeID()
        let submitID = NodeID()
        let options = [
            InternalFormOption(id: FormOptionID(), label: "One & <two>", value: "one"),
            InternalFormOption(id: FormOptionID(), label: "Three", value: "three"),
        ]
        let nodes = [
            formNode(formID),
            InternalRenderTreeNode(id: selectID, sourceNodeID: selectID, paintOrder: 1, frame: Self.frame, semanticElement: "p", cssSelector: "", formField: .init(kind: "select", label: "Plan", name: "plan", help: "Pick <one>", required: true, formID: formID, options: options)),
            InternalRenderTreeNode(id: checkboxID, sourceNodeID: checkboxID, paintOrder: 2, frame: Self.frame, semanticElement: "p", cssSelector: "", formField: .init(kind: "checkbox", label: "Accept terms", name: "terms", help: nil, required: true, formID: formID, options: [])),
            InternalRenderTreeNode(id: submitID, sourceNodeID: submitID, paintOrder: 3, frame: Self.frame, semanticElement: "p", cssSelector: "", formField: .init(kind: "submit", label: "Send", name: "send", help: nil, required: false, formID: formID, options: [])),
        ]
        let output = try SafeHTMLEmitter.emit(.init(documentID: DocumentID(), revision: 2, nodes: nodes))
        XCTAssertTrue(output.contains("<select"))
        XCTAssertTrue(output.contains("<option value=\"one\">One &amp; &lt;two&gt;</option>"))
        XCTAssertTrue(output.contains("Pick &lt;one&gt;"))
        XCTAssertTrue(output.contains("name=\"terms\" type=\"checkbox\" required"))
        XCTAssertTrue(output.contains("type=\"submit\" disabled aria-disabled=\"true\" data-siteforge-submission=\"unconfigured\""))
    }

    func testSafeCSSEmitterAddsOnlyFixedFormControlBaseline() throws {
        let formID = NodeID(), fieldID = NodeID()
        let tree = InternalRenderTreeSnapshot(documentID: DocumentID(), revision: 1, nodes: [
            formNode(formID),
            .init(id: fieldID, sourceNodeID: fieldID, paintOrder: 1, frame: Self.frame, semanticElement: "p", cssSelector: "", formField: .init(kind: "text", label: "Name", name: "name", help: nil, required: false, formID: formID, options: [])),
        ])
        let css = try SafeCSSEmitter.emit(tree)
        XCTAssertTrue(css.contains("form input, form select, form textarea, form button"))
        XCTAssertTrue(css.contains("form button[disabled]"))
        XCTAssertFalse(css.contains("Name"))
    }

    func testResponsiveStaticCSSEmitterUsesOnlyTypedProductBreakpoints() {
        let id = NodeID()
        let node = DocumentNode(id: id, kind: .frame, name: "Frame", parent: .page(PageID()), properties: [
            .init(key: .init(rawValue: "layout.x"), value: .number(0), origin: .defaulted),
            .init(key: .init(rawValue: "layout.y"), value: .number(0), origin: .defaulted),
            .init(key: .init(rawValue: "layout.width"), value: .number(100), origin: .defaulted),
            .init(key: .init(rawValue: "layout.height"), value: .number(100), origin: .defaulted),
            .init(key: .init(rawValue: ResponsiveGeometryResolver.key(.x, breakpoint: .tablet)), value: .number(48), origin: .authored),
            .init(key: .init(rawValue: ResponsiveGeometryResolver.key(.width, breakpoint: .mobile)), value: .number(280), origin: .authored),
            .init(key: .init(rawValue: ResponsiveVisibilityResolver.key(.mobile)), value: .boolean(false), origin: .authored),
        ])
        let output = ResponsiveStaticCSSEmitter.emit(nodes: [node])
        XCTAssertTrue(output.css.contains("min-width: 600px) and (width < 1024px)"))
        XCTAssertTrue(output.css.contains("left: 48.0px;"))
        XCTAssertTrue(output.css.contains("width < 600px"))
        XCTAssertTrue(output.css.contains("width: 280.0px;"))
        XCTAssertTrue(output.css.contains("display: none;"))
        XCTAssertEqual(output.report.appliedRuleCount, 2)
    }

    // SF-1204-003, SF-0601-003, SF-0603-003 — base geometry, responsive
    // overrides, and visibility all use the same typed property cascade.
    func testStaticLayoutOutputUsesStableRoundingAndExplicitVisibilityOverrides() {
        let id = NodeID()
        let node = DocumentNode(id: id, kind: .frame, name: "Frame", parent: .page(PageID()), properties: [
            .init(key: .init(rawValue: "layout.x"), value: .number(-0.0001), origin: .defaulted),
            .init(key: .init(rawValue: "layout.y"), value: .number(20), origin: .defaulted),
            .init(key: .init(rawValue: "layout.width"), value: .number(100), origin: .defaulted),
            .init(key: .init(rawValue: "layout.height"), value: .number(80), origin: .defaulted),
            .init(key: .init(rawValue: "hidden"), value: .boolean(true), origin: .authored),
            .init(key: .init(rawValue: ResponsiveGeometryResolver.key(.x, breakpoint: .tablet)), value: .number(48.23456), origin: .authored),
            .init(key: .init(rawValue: ResponsiveVisibilityResolver.key(.mobile)), value: .boolean(true), origin: .authored),
        ])
        let output = StaticLayoutOutputEmitter.emit(nodes: [node])
        XCTAssertTrue(output.css.contains("box-sizing: border-box;"))
        XCTAssertTrue(output.css.contains("left: 0.0px;"))
        XCTAssertTrue(output.css.contains("display: none;"))
        XCTAssertTrue(output.css.contains("left: 48.235px;"))
        XCTAssertTrue(output.css.contains("@media (width < 600px)"))
        XCTAssertTrue(output.css.contains("display: block;"))
        XCTAssertEqual(output.report.baseRuleCount, 1)
        XCTAssertEqual(output.report.breakpoints, [.tablet, .mobile])
    }

    // SF-0507-003, SF-1203-003, SF-1204-003 — static text remains escaped
    // while only closed canonical typography values reach the stylesheet.
    func testManagedTitleOverflowLeavesOrdinaryMultilineAndControlsUnchanged() throws {
        let bodyID = NodeID(), titleID = NodeID(), rect = WorldRect(origin: .init(x: 0, y: 0), size: .init(width: 200, height: 72))
        let body = InternalRenderTreeNode(id: bodyID, sourceNodeID: bodyID, paintOrder: 0, frame: rect,
            semanticElement: "p", cssSelector: CanonicalCSSRule.selector(for: bodyID), formField: nil,
            textContent: "Body  keeps\nhard line breaks", typography: CanonicalTypography.defaultValue)
        let title = InternalRenderTreeNode(id: titleID, sourceNodeID: titleID, paintOrder: 1, frame: rect,
            semanticElement: "h2", cssSelector: CanonicalCSSRule.selector(for: titleID), formField: nil,
            textContent: "Short", typography: CanonicalTypography.defaultValue, isManagedChromeTitle: true)
        let bodyCSS = StaticTypographyOutputEmitter.emit(nodes: [body])
        XCTAssertTrue(bodyCSS.contains("white-space: pre-wrap;"))
        XCTAssertFalse(bodyCSS.contains("line-clamp"))
        XCTAssertFalse(bodyCSS.contains("sf-text-height"))
        let html = try SafeHTMLEmitter.emit(.init(documentID: DocumentID(), revision: 4, nodes: [body, title]))
        XCTAssertTrue(html.contains("Body  keeps\nhard line breaks</p>"))
        XCTAssertTrue(html.contains("<span data-siteforge-text>Short</span></h2>"))
        XCTAssertEqual(html.components(separatedBy: "data-siteforge-text").count - 1, 1)
        XCTAssertFalse(html.contains("tabindex"))
        XCTAssertFalse(html.contains("aria-hidden"))
        XCTAssertEqual(CanvasTextLayoutPolicy.visibleLineCapacity(height: rect.size.height, lineHeight: 17), 4)
        let controlID = NodeID()
        let control = InternalRenderTreeNode(id: controlID, sourceNodeID: controlID, paintOrder: 2,
            frame: rect, semanticElement: "a", cssSelector: CanonicalCSSRule.selector(for: controlID), formField: nil,
            control: .init(label: "Visit", href: "/", isLink: true, opensNewContext: false, disabled: false),
            typography: CanonicalTypography.defaultValue)
        let controlCSS = StaticTypographyOutputEmitter.emit(nodes: [control])
        XCTAssertTrue(controlCSS.contains(":is(a,button) { display:flex;align-items:center;"))
        XCTAssertFalse(controlCSS.contains("line-clamp"))
        let controlHTML = try SafeHTMLEmitter.emit(.init(documentID: DocumentID(), revision: 4, nodes: [control]))
        XCTAssertTrue(controlHTML.contains("href=\"/\">Visit</a>"))
        XCTAssertFalse(controlHTML.contains("data-siteforge-text"))
    }

    func testStaticTypographyOutputEscapesTextAndUsesAllowlistedCanonicalValues() throws {
        let pageID = PageID(), nodeID = NodeID()
        let node = DocumentNode(id: nodeID, kind: .text, name: "Heading", parent: .page(pageID), properties: [
            .init(key: .init(rawValue: "content.text"), value: .string("Hello <SiteForge> & friends"), origin: .authored),
            .init(key: .init(rawValue: CanonicalTypography.namespace + "family"), value: .string(CanonicalTypography.defaultFamily), origin: .defaulted),
            .init(key: .init(rawValue: CanonicalTypography.namespace + "weight"), value: .string("bold"), origin: .authored),
            .init(key: .init(rawValue: CanonicalTypography.namespace + "size"), value: .number(18.5), origin: .authored),
            .init(key: .init(rawValue: CanonicalTypography.namespace + "lineHeight"), value: .number(24), origin: .authored),
            .init(key: .init(rawValue: CanonicalTypography.namespace + "tracking"), value: .number(0.25), origin: .authored),
            .init(key: .init(rawValue: CanonicalTypography.namespace + "alignment"), value: .string("center"), origin: .authored),
        ])
        let page = DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home,
                                rootNodeIDs: [nodeID], nodes: [node])
        let tree = try InternalDocumentRenderTreeCompiler.compile(page: page, documentID: DocumentID(), revision: 1)

        XCTAssertTrue(try SafeHTMLEmitter.emit(tree).contains("Hello &lt;SiteForge&gt; &amp; friends"))
        let css = StaticTypographyOutputEmitter.emit(nodes: tree.nodes)
        XCTAssertTrue(css.contains(CanonicalCSSRule.selector(for: nodeID)))
        XCTAssertTrue(css.contains("font-family: system-ui;"))
        XCTAssertTrue(css.contains("font-weight: 700;"))
        XCTAssertTrue(css.contains("font-size: 18.5px;"))
        XCTAssertTrue(css.contains("text-align: center;"))
        XCTAssertTrue(css.contains("white-space: pre-wrap;"))
        XCTAssertTrue(css.contains("[data-siteforge-node] { display:flex;flex-direction:column;justify-content:center;overflow:hidden; }"))
        var authored = node
        authored.properties[1].value = .string("Georgia")
        authored.properties[1].origin = .authored
        let serifPage = DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home,
            rootNodeIDs: [nodeID], nodes: [authored])
        let serif = try InternalDocumentRenderTreeCompiler.compile(page: serifPage, documentID: DocumentID(), revision: 2)
        XCTAssertTrue(StaticTypographyOutputEmitter.emit(nodes: serif.nodes).contains("font-family: \"Georgia\", system-ui;"))
        authored.properties[1].value = .string("A\";color:red;/*")
        let hostilePage = DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home,
            rootNodeIDs: [nodeID], nodes: [authored])
        let literal = try InternalDocumentRenderTreeCompiler.compile(page: hostilePage, documentID: DocumentID(), revision: 3)
        let escaped = StaticTypographyOutputEmitter.emit(nodes: literal.nodes)
        XCTAssertTrue(escaped.contains("\\22 "))
        XCTAssertFalse(escaped.contains(";color:red;"))
    }

    // SF-AUTHORING-098, SF-1203-003/004 — canonical accessibility metadata
    // reaches the immutable canvas/static projections as escaped semantics,
    // never as executable markup or editor-only chrome.
    func testCanonicalAccessibilityMetadataReachesSafeStaticOutput() throws {
        let pageID = PageID(), nodeID = NodeID()
        let node = DocumentNode(id: nodeID, kind: .frame, name: "Hero", parent: .page(pageID), properties: [
            .init(key: .init(rawValue: CanonicalAccessibilityMetadata.Field.name.key),
                  value: .string("Hero <region>"), origin: .authored),
            .init(key: .init(rawValue: CanonicalAccessibilityMetadata.Field.help.key),
                  value: .string("Introduces & summarizes this page."), origin: .authored),
        ])
        let page = DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home,
                                rootNodeIDs: [nodeID], nodes: [node])
        let tree = try InternalDocumentRenderTreeCompiler.compile(
            page: page, documentID: DocumentID(), revision: 1
        )
        let output = try SafeHTMLEmitter.emit(tree)
        XCTAssertTrue(output.contains("aria-label=\"Hero &lt;region&gt;\""))
        XCTAssertTrue(output.contains("aria-description=\"Introduces &amp; summarizes this page.\""))
        XCTAssertFalse(output.contains("selection"))
    }

    func testSafeHTMLEmitterRejectsNonFormOrMalformedSelectControls() throws {
        let nodeID = NodeID()
        let orphan = InternalRenderTreeNode(id: nodeID, sourceNodeID: nodeID, paintOrder: 0, frame: Self.frame, semanticElement: "p", cssSelector: "", formField: .init(kind: "select", label: "Plan", name: "plan", help: nil, required: false, formID: NodeID(), options: [.init(id: FormOptionID(), label: "One", value: "one")]))
        XCTAssertThrowsError(try SafeHTMLEmitter.emit(.init(documentID: DocumentID(), revision: 1, nodes: [orphan])))

        let formID = NodeID()
        let malformed = InternalRenderTreeNode(id: nodeID, sourceNodeID: nodeID, paintOrder: 1, frame: Self.frame, semanticElement: "p", cssSelector: "", formField: .init(kind: "select", label: "Plan", name: "plan", help: nil, required: false, formID: formID, options: [.init(id: FormOptionID(), label: "", value: "one")]))
        XCTAssertThrowsError(try SafeHTMLEmitter.emit(.init(documentID: DocumentID(), revision: 1, nodes: [formNode(formID), malformed])))
    }

    func testCanonicalFormSelectOptionsPreserveStableOrderAndRejectUnsafeValues() throws {
        let first = CanonicalFormSelectOption(label: "Starter", value: "starter")
        let second = CanonicalFormSelectOption(label: "Professional", value: "pro")
        let encoded = try CanonicalFormSelectOptions.encode([first, second])
        XCTAssertEqual(try CanonicalFormSelectOptions.decode(encoded), [first, second])
        XCTAssertThrowsError(try CanonicalFormSelectOptions.encode([
            .init(id: first.id, label: "Duplicate identity", value: "other"),
            .init(id: first.id, label: "Also duplicate", value: "another"),
        ]))
        XCTAssertThrowsError(try CanonicalFormSelectOptions.encode([
            first,
            .init(label: "Duplicate value", value: "starter"),
        ]))
        XCTAssertThrowsError(try CanonicalFormSelectOptions.decode("[]"))
    }

    private static let frame = WorldRect(origin: .init(x: 0, y: 0), size: .init(width: 1, height: 1))

    private func typedControlProperties(
        _ target: CanonicalLinkTarget,
        label: String,
        context: CanonicalLinkContext = .same
    ) -> [NodeProperty] {
        target.properties.map { .init(key: .init(rawValue: $0.0), value: $0.1) } + [
            .init(key: .init(rawValue: CanonicalLinkTarget.labelKey), value: .string(label)),
        ] + (context == .new ? [
            .init(key: .init(rawValue: CanonicalLinkTarget.namespace + "context"), value: .string(context.rawValue)),
        ] : [])
    }

    private func formNode(_ id: NodeID) -> InternalRenderTreeNode {
        .init(id: id, sourceNodeID: id, paintOrder: 0, frame: Self.frame, semanticElement: "form", cssSelector: "", formField: nil)
    }
    func testSafeHTMLEmitterUsesFixedVocabularyAndStableIdentity() throws {
        let id = NodeID()
        let tree = InternalRenderTreeSnapshot(documentID: DocumentID(), revision: 4, nodes: [
            .init(id: id, sourceNodeID: id, paintOrder: 0, frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 0, height: 0)), semanticElement: "article", cssSelector: "ignored", formField: nil)
        ])
        let output = try SafeHTMLEmitter.emit(tree)
        XCTAssertEqual(output, "<article data-siteforge-node=\"\(id.rawValue.uuidString.lowercased())\" class=\"sf-node-\(id.rawValue.uuidString.lowercased())\"></article>")
        XCTAssertThrowsError(try SafeHTMLEmitter.emit(.init(documentID: tree.documentID, revision: 4, nodes: [
            .init(id: id, sourceNodeID: id, paintOrder: 0, frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 0, height: 0)), semanticElement: "script", cssSelector: "", formField: nil)
        ])))
    }

    func testSafeCSSEmitterUsesFixedOrderedGeometryOnly() throws {
        let id = NodeID()
        let node = InternalRenderTreeNode(id: id, sourceNodeID: id, paintOrder: 0,
            frame: .init(origin: .init(x: 4, y: 5), size: .init(width: 6, height: 7)), semanticElement: "div", cssSelector: "", formField: nil)
        XCTAssertEqual(try SafeCSSEmitter.emit(.init(documentID: DocumentID(), revision: 1, nodes: [node])),
            "[data-siteforge-node=\"\(id.rawValue.uuidString.lowercased())\"] { height: 7.0px; left: 4.0px; position: absolute; top: 5.0px; width: 6.0px; }")
    }
    func testLocalStaticBuildWriterStagesDeterministicOutputAndRejectsStale() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let plan = LocalStaticBuildPlan(revision: 2, files: [.init(path: "index.html", contents: "ok"), .init(path: "styles.css", contents: "css")])
        let destination = root.appendingPathComponent("build")
        try LocalStaticBuildWriter.write(plan, to: destination, expectedRevision: 2)
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("index.html")), "ok")
        XCTAssertThrowsError(try LocalStaticBuildWriter.write(plan, to: destination, expectedRevision: 3))
    }

    // OD-042, SF-1209: the zip adapter carries exactly the plan's files and the
    // same plan always gives the same bytes.
    func testZipExportArchiveIsDeterministicStoredAndRoundTripsEveryPlanFile() throws {
        let image = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF])
        let plan = LocalStaticBuildPlan(revision: 4, files: [
            .init(path: "styles.css", contents: "body{}"),
            .init(path: "index.html", contents: "<!doctype html><p>Café</p>"),
            .init(path: "about/index.html", contents: "about"),
        ], binaryFiles: [.init(path: "assets/a.png", contents: image)])
        let first = try StaticSiteZipArchive.archive(plan)
        let reordered = LocalStaticBuildPlan(revision: 4, files: Array(plan.files.reversed()), binaryFiles: plan.binaryFiles)
        XCTAssertEqual(try StaticSiteZipArchive.archive(reordered), first)

        let entries = try StaticSiteZipArchive.storedEntries(first)
        XCTAssertEqual(entries.map(\.path), ["about/index.html", "assets/a.png", "index.html", "styles.css"])
        XCTAssertEqual(entries.first { $0.path == "index.html" }?.data, Data("<!doctype html><p>Café</p>".utf8))
        XCTAssertEqual(entries.first { $0.path == "assets/a.png" }?.data, image)

        // CRC-32 check value, signatures, stored method and the DOS epoch timestamp.
        XCTAssertEqual(StaticSiteZipArchive.crc32(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(Array(first.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        XCTAssertEqual(Array(first.suffix(22).prefix(4)), [0x50, 0x4B, 0x05, 0x06])
        XCTAssertEqual(Array(first[8..<14]), [0, 0, 0, 0, 0x21, 0])

        XCTAssertThrowsError(try StaticSiteZipArchive.archive(.init(revision: 1, files: [.init(path: "../escape", contents: "x")]))) {
            XCTAssertEqual($0 as? StaticSiteZipArchive.ArchiveError, .unsafePath)
        }
        XCTAssertThrowsError(try StaticSiteZipArchive.archive(.init(revision: 1, files: [
            .init(path: "a.html", contents: "1"), .init(path: "a.html", contents: "2"),
        ]))) { XCTAssertEqual($0 as? StaticSiteZipArchive.ArchiveError, .duplicatePath) }

        // First entry data starts after the 30-byte header and the 16-byte name.
        var corrupt = first
        corrupt[corrupt.startIndex + 47] ^= 0xFF
        XCTAssertThrowsError(try StaticSiteZipArchive.storedEntries(corrupt)) {
            XCTAssertEqual($0 as? StaticSiteZipArchive.ArchiveError, .malformed)
        }
        XCTAssertThrowsError(try StaticSiteZipArchive.storedEntries(Data(first.dropLast())))
    }

    // OD-042, SF-1209: the zip writer has the folder writer's revision,
    // replacement, cancellation and destination rules and leaves nothing behind.
    func testZipExportWriterStagesVerifiesReplacesAndRefusesUnsafeTargets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let plan = LocalStaticBuildPlan(revision: 2, files: [.init(path: "index.html", contents: "ok")])
        let destination = root.appendingPathComponent("Website.zip")
        try LocalStaticBuildWriter.writeZipArchive(plan, to: destination, expectedRevision: 2)
        XCTAssertEqual(try Data(contentsOf: destination), try StaticSiteZipArchive.archive(plan))

        XCTAssertThrowsError(try LocalStaticBuildWriter.writeZipArchive(plan, to: destination, expectedRevision: 2)) {
            XCTAssertEqual($0 as? LocalStaticBuildWriteError, .destinationExists)
        }
        XCTAssertThrowsError(try LocalStaticBuildWriter.writeZipArchive(plan, to: destination, expectedRevision: 3)) {
            XCTAssertEqual($0 as? LocalStaticBuildWriteError, .stale)
        }
        let next = LocalStaticBuildPlan(revision: 3, files: [.init(path: "index.html", contents: "next")])
        try LocalStaticBuildWriter.writeZipArchive(next, to: destination, expectedRevision: 3, replacingExisting: true)
        XCTAssertEqual(try StaticSiteZipArchive.storedEntries(Data(contentsOf: destination)).map(\.data), [Data("next".utf8)])

        XCTAssertThrowsError(try LocalStaticBuildWriter.writeZipArchive(plan, to: root.appendingPathComponent("Website"),
                                                                        expectedRevision: 2)) {
            XCTAssertEqual($0 as? LocalStaticBuildWriteError, .unsafeDestination)
        }
        let folder = root.appendingPathComponent("Folder.zip")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        XCTAssertThrowsError(try LocalStaticBuildWriter.writeZipArchive(plan, to: folder, expectedRevision: 2,
                                                                        replacingExisting: true)) {
            XCTAssertEqual($0 as? LocalStaticBuildWriteError, .unsafeDestination)
        }
        let unsafe = LocalStaticBuildPlan(revision: 2, files: [.init(path: "../escape.html", contents: "x")])
        XCTAssertThrowsError(try LocalStaticBuildWriter.writeZipArchive(unsafe, to: root.appendingPathComponent("Unsafe.zip"),
                                                                        expectedRevision: 2)) {
            XCTAssertEqual($0 as? LocalStaticBuildWriteError, .unsafeDestination)
        }
        let cancelled = root.appendingPathComponent("Cancelled.zip")
        XCTAssertThrowsError(try LocalStaticBuildWriter.writeZipArchive(plan, to: cancelled, expectedRevision: 2, cancelled: true)) {
            XCTAssertEqual($0 as? LocalStaticBuildWriteError, .cancelled)
        }
        let checkpointCancelled = root.appendingPathComponent("CheckpointCancelled.zip")
        XCTAssertThrowsError(try LocalStaticBuildWriter.writeZipArchive(plan, to: checkpointCancelled, expectedRevision: 2,
            cancellation: .init { throw CancellationError() })) {
            XCTAssertEqual($0 as? LocalStaticBuildWriteError, .cancelled)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelled.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkpointCancelled.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".siteforge-build-") }, [])
    }

    // SF-1209-003/004/008 (OD-042, ADR-0145): the zip target reports a plan it
    // cannot carry before anything is written, the size check matches the real
    // archive, and export diagnostics name the target without paths or content.
    func testZipExportTargetReportsUnsupportedPlansBeforeWritingWithValueFreeDiagnostics() throws {
        let plan = LocalStaticBuildPlan(revision: 5, files: [.init(path: "index.html", contents: "<p>Café</p>"),
            .init(path: "about.html", contents: "about")], binaryFiles: [.init(path: "assets/a.png", contents: Data([1, 2, 3]))])
        XCTAssertEqual(StaticSiteZipArchive.archivedByteCount(plan), try StaticSiteZipArchive.archive(plan).count)
        XCTAssertTrue(StaticSiteZipArchive.canArchive(plan))
        XCTAssertNil(StaticExportTarget.zipArchive.unsupportedReason(for: plan))
        XCTAssertNil(StaticExportTarget.folder.unsupportedReason(for: plan))

        let crowded = LocalStaticBuildPlan(revision: 5, files: (0...StaticSiteZipArchive.maximumEntryCount).map {
            LocalStaticBuildPlan.File(path: "p\($0).html", contents: "")
        })
        XCTAssertFalse(StaticSiteZipArchive.canArchive(crowded))
        XCTAssertNotNil(StaticExportTarget.zipArchive.unsupportedReason(for: crowded))
        XCTAssertNil(StaticExportTarget.folder.unsupportedReason(for: crowded), "A folder has no entry limit")
        XCTAssertThrowsError(try StaticSiteZipArchive.archive(crowded)) {
            XCTAssertEqual($0 as? StaticSiteZipArchive.ArchiveError, .tooLarge)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertThrowsError(try LocalStaticBuildWriter.writeZipArchive(crowded, to: root.appendingPathComponent("Crowded.zip"),
                                                                        expectedRevision: 5)) {
            XCTAssertEqual($0 as? LocalStaticBuildWriteError, .archiveTooLarge)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [], "Nothing is staged or written")

        let documentID = DocumentID()
        let success = StaticExportDiagnostic(target: .zipArchive, documentID: documentID, plan: plan,
                                             duration: .milliseconds(12), failure: nil)
        XCTAssertEqual(success.requirementID, "SF-1209-008")
        XCTAssertEqual(success.operation, "export")
        XCTAssertEqual(success.target, .zipArchive)
        XCTAssertEqual(success.revision, 5)
        XCTAssertEqual(success.fileCount, 3)
        XCTAssertEqual(success.durationMilliseconds, 12)
        XCTAssertEqual(success.failureCategory, "none")
        XCTAssertTrue(success.documentToken.hasPrefix("document-"))
        XCTAssertFalse(success.documentToken.contains(documentID.description))
        let failure = StaticExportDiagnostic(target: .folder, documentID: documentID, plan: plan,
                                             duration: .zero, failure: .archiveTooLarge)
        XCTAssertEqual(failure.failureCategory, "archive-too-large")
        XCTAssertEqual(failure.documentToken, success.documentToken, "The token is stable for one document")
        let categories = [LocalStaticBuildWriteError.unsafeDestination, .destinationExists, .stale, .cancelled,
                          .insufficientSpace, .permissionDenied, .writeFailed, .archiveTooLarge].map(\.diagnosticCategory)
        XCTAssertEqual(Set(categories).count, categories.count, "Every failure has its own category")
    }

    // SF-1107-003/004 (OD-041): Check Website builds place site then page
    // custom code verbatim in the head, a trailing style and the end of the
    // body; Browser Preview leaves it out; findings name it without its text.
    func testCustomCodeIsWrittenVerbatimToBuildsAndLeftOutOfPreview() throws {
        var document = ProjectCreation.blank()
        let about = DocumentPage(name: "About", route: .init(rawValue: "/about"))
        document.pages.append(about)
        let siteHead = "<meta name=\"site-verification\" content=\"abc123\">"
        let siteCSS = ".sf-custom-banner { color: rebeccapurple; }"
        let pageBody = "<div id=\"booking-widget\"></div>\n<script src=\"https://widgets.example/book.js\" async></script>"
        document.websiteMetadata = WebsiteMetadata(siteName: "Studio",
            pages: [PageWebsiteMetadata(pageID: about.id, customCode: CustomCodeBlock(bodyHTML: pageBody, css: ".about { margin: 0; }"))],
            customCode: CustomCodeBlock(headHTML: siteHead, css: siteCSS))
        try document.validate()

        let build = StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .staticRelease),
                                                resourceDescriptors: [:], resourceData: [:])
        let plan = try XCTUnwrap(build.plan, "\(build.findings.map(\.code))")
        XCTAssertTrue(build.canWrite)
        let home = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        let aboutHTML = try XCTUnwrap(plan.files.first { $0.path == "about.html" }?.contents)
        for html in [home, aboutHTML] {
            let headEnd = try XCTUnwrap(html.range(of: "</head>"))
            let metaRange = try XCTUnwrap(html.range(of: siteHead))
            XCTAssertLessThan(metaRange.upperBound, headEnd.lowerBound, "Site head code is inside the head")
            let style = try XCTUnwrap(html.range(of: "<style data-siteforge-custom-code>"))
            XCTAssertLessThan(style.upperBound, headEnd.lowerBound)
            XCTAssertLessThan(metaRange.lowerBound, style.lowerBound, "HTML first, then CSS")
            XCTAssertTrue(html.contains(siteCSS))
        }
        XCTAssertFalse(home.contains("booking-widget"), "Page code stays on its page")
        XCTAssertFalse(home.contains(".about { margin: 0; }"))
        let bodyCode = try XCTUnwrap(aboutHTML.range(of: pageBody), "Written exactly as entered")
        let bodyEnd = try XCTUnwrap(aboutHTML.range(of: "</body>"))
        XCTAssertLessThan(bodyCode.upperBound, bodyEnd.lowerBound)
        XCTAssertGreaterThan(bodyCode.lowerBound, try XCTUnwrap(aboutHTML.range(of: "<body")).upperBound)
        let siteCSSRange = try XCTUnwrap(aboutHTML.range(of: siteCSS))
        XCTAssertLessThan(siteCSSRange.upperBound, try XCTUnwrap(aboutHTML.range(of: ".about { margin: 0; }")).lowerBound,
                          "Site CSS first, then the page's")
        let codes = build.findings.map(\.code)
        XCTAssertTrue(codes.contains("custom-code-unvalidated"))
        XCTAssertTrue(codes.contains("custom-code-script"))
        // SF-1107-004 (ADR-0145): the script finding names the page by its output file.
        XCTAssertEqual(build.findings.filter { $0.code == "custom-code-script" }.map(\.outputPath), ["about.html"])
        XCTAssertFalse(codes.contains("custom-code-excluded-from-preview"))
        XCTAssertFalse(build.redactedSummary.contains("booking"), "Findings carry no authored code")
        XCTAssertFalse(build.redactedSummary.contains("abc123"))
        XCTAssertFalse(build.report?.deferredCapabilities.contains("custom-code") ?? true)

        let preview = StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .development),
                                                  resourceDescriptors: [:], resourceData: [:], includesCustomCode: false)
        let previewPlan = try XCTUnwrap(preview.plan)
        let previewText = previewPlan.files.map(\.contents).joined()
        XCTAssertFalse(previewText.contains("site-verification"))
        XCTAssertFalse(previewText.contains("booking-widget"))
        XCTAssertFalse(previewText.contains("data-siteforge-custom-code"))
        XCTAssertEqual(preview.findings.filter { $0.code.hasPrefix("custom-code") }.map(\.code), ["custom-code-excluded-from-preview"])

        // Without custom code the output is unchanged and nothing is reported.
        var plain = document
        plain.websiteMetadata = WebsiteMetadata(siteName: "Studio")
        let plainBuild = StaticBuildCompiler.compile(document: plain, profileSelection: .init(profile: .staticRelease),
                                                     resourceDescriptors: [:], resourceData: [:])
        XCTAssertFalse(plainBuild.findings.contains { $0.code.hasPrefix("custom-code") })
        XCTAssertEqual(try MultiPageStaticBuildPlanner.plan(document: plain, includesCustomCode: true),
                       try MultiPageStaticBuildPlanner.plan(document: plain, includesCustomCode: false))
    }

    // OD-042, SF-1209, SF-1211-004: Browser Preview exports the successful
    // website as one zip with the same files Safari was served.
    @MainActor func testBrowserPreviewZipExportUsesTheSuccessfulPreviewPlan() async throws {
        let fixture = try ApplicationOwnedTestFixture.create("preview-zip-export")
        defer { try? fixture.cleanup() }
        let document = ProjectCreation.blank()
        let controller = BrowserPreviewController { _ in .opened }
        defer { controller.stop() }
        await controller.build(document: document, pageID: document.pages[0].id,
            package: .init(document: document), isCurrent: { _, _ in true }).value
        let plan = try XCTUnwrap(controller.plan)
        let destination = fixture.url.appendingPathComponent("Website.zip")
        let export = try XCTUnwrap(controller.export(to: destination, target: .zipArchive))
        await export.value
        XCTAssertFalse(controller.isExporting)
        XCTAssertNil(controller.exportFailure, controller.status)
        let entries = try StaticSiteZipArchive.storedEntries(Data(contentsOf: destination))
        XCTAssertEqual(Set(entries.map(\.path)), Set(plan.files.map(\.path) + plan.binaryFiles.map(\.path)))
        for file in plan.files {
            XCTAssertEqual(entries.first { $0.path == file.path }?.data, Data(file.contents.utf8))
        }
        XCTAssertTrue(controller.status.contains("zip archive"), controller.status)
        // SF-1209-004/008 (ADR-0145): each export leaves a value-free diagnostic;
        // an existing archive is not replaced without confirmation.
        let diagnostic = try XCTUnwrap(controller.lastExportDiagnostic)
        XCTAssertEqual(diagnostic.target, .zipArchive)
        XCTAssertEqual(diagnostic.failureCategory, "none")
        XCTAssertEqual(diagnostic.fileCount, plan.files.count + plan.binaryFiles.count)
        let exported = try Data(contentsOf: destination)
        let again = try XCTUnwrap(controller.export(to: destination, target: .zipArchive))
        await again.value
        XCTAssertEqual(controller.exportFailure, .destinationExists)
        XCTAssertEqual(controller.lastExportDiagnostic?.failureCategory, "destination-exists")
        XCTAssertEqual(try Data(contentsOf: destination), exported, "The existing archive is unchanged")
    }

    // SF-1204-003/004/008, SF-1208-003/004/008, SF-1211-003/004/008
    func testStaticBuildCompilerProfilesAreDeterministicRedactedAndCancellationNeutral() throws {
        let pageID = PageID(), nodeID = NodeID()
        let node = DocumentNode(id: nodeID, kind: .frame, name: "Private authored name",
            parent: .page(pageID), properties: [
                .init(key: .init(rawValue: "layout.x"), value: .number(12), origin: .authored),
                .init(key: .init(rawValue: "layout.y"), value: .number(24), origin: .authored),
                .init(key: .init(rawValue: "layout.width"), value: .number(200), origin: .authored),
                .init(key: .init(rawValue: "layout.height"), value: .number(100), origin: .authored),
            ])
        let page = DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home,
                                rootNodeIDs: [nodeID], nodes: [node])
        let document = CanonicalDocument(pages: [page])
        let first = StaticBuildCompiler.compile(document: document,
            profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:])
        let second = StaticBuildCompiler.compile(document: document,
            profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:])
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.canWrite)
        XCTAssertEqual(first.plan?.integrityDigest, second.plan?.integrityDigest)
        XCTAssertFalse(first.redactedSummary.contains("Private authored name"))
        XCTAssertFalse(first.redactedSummary.contains(nodeID.description))
        XCTAssertTrue(first.findings.contains { $0.code == "publishing-excluded" })

        let release = StaticBuildCompiler.compile(document: document,
            profileSelection: .init(profile: .staticRelease), resourceDescriptors: [:], resourceData: [:])
        XCTAssertTrue(release.canWrite)
        XCTAssertEqual(release.report?.profile, .staticRelease)
        let releasePaths = try XCTUnwrap(release.plan?.files.map(\.path))
        XCTAssertEqual(releasePaths, releasePaths.sorted())

        let cancelled = StaticBuildCompiler.compile(document: document,
            profileSelection: .init(profile: .development), resourceDescriptors: [:],
            resourceData: [:], cancelled: true)
        XCTAssertNil(cancelled.plan)
        XCTAssertEqual(cancelled.findings.map(\.code), ["cancelled"])
    }

    // SF-1204-003/004/008 (OD-042, ADR-0120): Static Release CSS is minified
    // statement by statement without reordering; only rules that cannot change
    // the result are removed, and anything unrecognized is written unchanged.
    func testStaticReleaseCSSOptimizerMinifiesDeduplicatesAndKeepsBlocksWhole() throws {
        let usedNode = NodeID(), otherNode = NodeID(), absentNode = NodeID()
        let used = usedNode.rawValue.uuidString.lowercased()
        let other = otherNode.rawValue.uuidString.lowercased()
        let absent = absentNode.rawValue.uuidString.lowercased()
        let css = """
        [data-siteforge-node="\(used)"] { height: 100px; left: 12px; }
        [data-siteforge-node="\(used)"] { height: 100px; left: 12px; }
        [data-siteforge-node="\(other)"] { color: red; color: blue; color: red; }
        .sf-empty { }
        form input, form select ,  form textarea > b { max-width: calc( 100vw - 32px ); }
        .x::after { content: "a;b{c}  d"; background: url(data:image/png;base64,AAA=) , rgba( 0 , 0 , 0 , .5 ); }
        :root { --sf-gap: 1px , 2px; }
        @media (prefers-color-scheme:dark) {
        [data-siteforge-node="\(other)"] { color: white; }
        }
        /* generated */
        @keyframes sf-entrance-fade { from { opacity:0; transform: translateY( 8px ); } }
        @container hero (min-width: 600px) { [data-siteforge-node="\(absent)"] { width: 50%; } }
        .sf-motion-ready [data-siteforge-node="\(absent)"]:not(.sf-motion-entered) { opacity:0; }
        .sf-flow-ready { isolation:isolate; }
        """
        let expected = "[data-siteforge-node=\"\(used)\"]{height:100px;left:12px}[data-siteforge-node=\"\(other)\"]{color:blue;color:red}form input,form select,form textarea>b{max-width:calc(100vw - 32px)}.x::after{content:\"a;b{c}  d\";background:url(data:image/png;base64,AAA=),rgba(0,0,0,.5)}:root{--sf-gap:1px , 2px}@media (prefers-color-scheme:dark){[data-siteforge-node=\"\(other)\"]{color:white}}@keyframes sf-entrance-fade{from{opacity:0;transform:translateY(8px)}}.sf-motion-ready [data-siteforge-node=\"\(absent)\"]:not(.sf-motion-entered){opacity:0}.sf-flow-ready{isolation:isolate}"
        let release = StaticCSSOptimizer.optimize(css, usedIdentifiers: [used, other])
        XCTAssertEqual(release.css, expected)
        XCTAssertTrue(release.report.isOptimized)
        XCTAssertNil(release.report.skippedReason)
        XCTAssertEqual(release.report.removedDuplicateRules, 1)
        XCTAssertEqual(release.report.removedDuplicateDeclarations, 1)
        XCTAssertEqual(release.report.removedUnusedRules, 1, "Only the rule whose selector has no :not(…)")
        XCTAssertEqual(release.report.removedEmptyRules, 2, "The empty rule and the container block left empty")
        XCTAssertEqual(release.report.originalBytes, css.utf8.count)
        XCTAssertEqual(release.report.outputBytes, expected.utf8.count)
        XCTAssertEqual(StaticCSSOptimizer.optimize(release.css, usedIdentifiers: [used, other]).css, release.css, "Idempotent")
        XCTAssertTrue(StaticCSSOptimizer.minify(css).contains("[data-siteforge-node=\"\(absent)\"]{width:50%}"),
                      "Without a used-object list every rule is kept")
        XCTAssertFalse(release.report.summary.contains(used), "The size report names no objects")

        // Regression: line-based de-duplication dropped the second block's closing brace.
        let blocks = "@media (min-width: 768px) {\n.a { color: red; }\n}\n@media (max-width: 767px) {\n.a { color: blue; }\n}"
        XCTAssertEqual(StaticCSSOptimizer.minify(blocks),
                       "@media (min-width: 768px){.a{color:red}}@media (max-width: 767px){.a{color:blue}}")

        // Fail closed: anything not fully understood is written unchanged and named.
        for unsafe in [".a { color: red; ", "@unknown x { .a { color: red; } }", ".a { .b { color: red; } }",
                       ".a { color }", ".a { color: red; } }", ".a { content: \"open; }"] {
            let skipped = StaticCSSOptimizer.optimize(unsafe, usedIdentifiers: [])
            XCTAssertEqual(skipped.css, unsafe)
            XCTAssertFalse(skipped.report.isOptimized, unsafe)
            XCTAssertNotNil(skipped.report.skippedReason, unsafe)
        }

        // SF-1204-003 provenance: the rules for one object, with their conditions.
        let trace = StaticCSSOptimizer.trace(css, nodeID: otherNode)
        XCTAssertEqual(trace.map(\.conditions), [[], ["@media (prefers-color-scheme:dark)"]])
        XCTAssertEqual(trace.map(\.declarations), [["color:red", "color:blue", "color:red"], ["color:white"]])

        // Profiles: Development keeps the stylesheet exactly; Static Release
        // writes the optimized text and leaves every other file unchanged.
        let plan = LocalStaticBuildPlan(revision: 3, files: [
            .init(path: "index.html", contents: "<div data-siteforge-node=\"\(used)\"></div><div data-siteforge-node=\"\(other)\"></div>"),
            .init(path: "styles.css", contents: css),
        ])
        let development = LocalBuildProfileCompiler.compile(plan, profile: .development)
        XCTAssertEqual(development.0.files, plan.files.sorted { $0.path < $1.path })
        XCTAssertEqual(development.1.cssReports, [.readable(path: "styles.css", css: css)])
        let staticRelease = LocalBuildProfileCompiler.compile(plan, profile: .staticRelease)
        XCTAssertEqual(staticRelease.0.files.first { $0.path == "styles.css" }?.contents, expected)
        XCTAssertEqual(staticRelease.0.files.first { $0.path == "index.html" }, plan.files.first { $0.path == "index.html" })
        XCTAssertEqual(staticRelease.1.cssReports, [release.report])
    }

    // SF-1206-001/003/004/008 (OD-042, ADR-0121): the integrity manifest lists every
    // written file with its hash and cache policy; relative references must resolve.
    func testStaticOutputIntegrityManifestCachePolicyAndReferenceAudit() throws {
        let hash = String(repeating: "b", count: 64)
        let picture = Data([0x89, 0x50, 0x4E, 0x47])
        let plan = LocalStaticBuildPlan(revision: 7, files: [
            .init(path: "index.html", contents: "<img src=\"assets/\(hash).png\"><a href=\"posts/first.html\">First</a><a href=\"https://example.com/x\">x</a><a href=\"#top\">Top</a><link rel=\"canonical\" href=\"/\"><a href=\"mailto:a@example.com\">Mail</a>"),
            .init(path: "posts/first.html", contents: "<img src=\"assets/\(hash).png\"><a href=\"../index.html\">Home</a><a href=\"missing.html?x=1#y\">Missing</a><div style=\"background:url(&quot;../assets/\(hash).png&quot;)\"></div>"),
            .init(path: "styles.css", contents: ".a{background:url(\"assets/\(hash).png\")}.b{background:url(assets/none.png)}.c{mask:url(#m)}.d{background:url(\"data:image/png;base64,AA==\")}"),
        ], binaryFiles: [.init(path: "assets/\(hash).png", contents: picture)])
        XCTAssertEqual(StaticOutputReferenceAudit.unresolved(in: plan), ["posts/first.html": 2, "styles.css": 1],
                       "A nested page's root-relative image and missing page, and one missing stylesheet image")

        let manifest = StaticOutputManifest(plan: plan)
        XCTAssertEqual(manifest.files.map(\.path), ["assets/\(hash).png", "index.html", "posts/first.html", "styles.css"])
        XCTAssertEqual(manifest.files.map(\.cache), [.immutable, .revalidate, .revalidate, .revalidate])
        XCTAssertEqual(manifest.files[0].sha256, ProjectResourceStore.digest(picture))
        XCTAssertEqual(manifest.files[0].bytes, picture.count)
        XCTAssertEqual(manifest.files[1].bytes, plan.files[0].contents.utf8.count)
        XCTAssertEqual(StaticOutputCachePolicy.policy(for: "assets/\(hash).PNG"), .revalidate)
        XCTAssertEqual(StaticOutputCachePolicy.policy(for: "assets/abc.png"), .revalidate)
        XCTAssertEqual(try JSONDecoder().decode(StaticOutputManifest.self, from: Data(manifest.json.utf8)), manifest)
        XCTAssertEqual(manifest.json, StaticOutputManifest(plan: plan).json, "Deterministic")
        XCTAssertFalse(manifest.json.contains("revision"), "Reproducible: no revision or time")
        XCTAssertEqual(manifest.mismatchedPaths(in: plan), [])
        let changed = LocalStaticBuildPlan(revision: 7, files: [plan.files[0], .init(path: "styles.css", contents: "")],
                                           binaryFiles: plan.binaryFiles)
        XCTAssertEqual(manifest.mismatchedPaths(in: changed), ["posts/first.html", "styles.css"])

        // Development writes no manifest; Static Release writes one that lists every other file.
        let development = LocalBuildProfileCompiler.compile(plan, profile: .development)
        XCTAssertFalse(development.0.files.contains { $0.path == StaticOutputManifest.fileName })
        XCTAssertEqual(development.1.outputFiles, manifest.files)
        let release = LocalBuildProfileCompiler.compile(plan, profile: .staticRelease)
        let written = try XCTUnwrap(release.0.files.first { $0.path == StaticOutputManifest.fileName }?.contents)
        let releaseManifest = try JSONDecoder().decode(StaticOutputManifest.self, from: Data(written.utf8))
        XCTAssertEqual(releaseManifest, StaticOutputManifest(plan: release.0), "Lists every other written file exactly")
        XCTAssertEqual(releaseManifest.files.count, release.0.files.count + release.0.binaryFiles.count - 1)
        XCTAssertEqual(release.1.outputFiles.filter { $0.path != StaticOutputManifest.fileName }, releaseManifest.files)
        // The report also lists the manifest file itself, so budgets count every written byte.
        let manifestRecord = try XCTUnwrap(release.1.outputFiles.first { $0.path == StaticOutputManifest.fileName })
        XCTAssertEqual(manifestRecord.bytes, written.utf8.count)
        XCTAssertEqual(manifestRecord.sha256, ProjectResourceStore.digest(Data(written.utf8)))
        XCTAssertEqual(release.1.outputFiles.map(\.path), release.1.filePaths, "Every written file, sorted")
        XCTAssertTrue(release.1.filePaths.contains(StaticOutputManifest.fileName))
        XCTAssertEqual(release.0.files.map(\.path), release.0.files.map(\.path).sorted())

        // SF-1206-004: over the per-file limit is oversized, an unknown type unsupported.
        let oversized = ProjectResourceDescriptor(id: ResourceID(), filename: "large.png", mediaType: "image/png",
            byteCount: ProjectResourceIndex.maximumResourceBytes + 1, sha256: hash)
        XCTAssertThrowsError(try StaticAssetExportPlanner.plan(index: .init(resources: [oversized]), blobs: [:])) {
            XCTAssertEqual($0 as? StaticAssetExportError, .oversized)
        }
        let unsupported = ProjectResourceDescriptor(id: ResourceID(), filename: "a.gif", mediaType: "image/gif",
            byteCount: 1, sha256: hash)
        XCTAssertThrowsError(try StaticAssetExportPlanner.plan(index: .init(resources: [unsupported]), blobs: [:])) {
            XCTAssertEqual($0 as? StaticAssetExportError, .unsupported)
        }

        // SF-1206-003: unused project images are named once, without file names.
        var document = ProjectCreation.blank()
        document.imageAssets = [ImageAsset(resourceID: ResourceID(), displayName: "Spare", originalFilename: "spare.png",
                                           format: .png, pixelWidth: 10, pixelHeight: 10, byteCount: 4, contentHash: hash)]
        let compiled = StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .development),
                                                   resourceDescriptors: [:], resourceData: [:])
        XCTAssertNotNil(compiled.plan, "\(compiled.findings.map(\.code))")
        let unused = try XCTUnwrap(compiled.findings.first { $0.code == "assets-unused" })
        XCTAssertEqual(unused.severity, .information)
        XCTAssertFalse(unused.explanation.contains("spare"), "No file names")
        XCTAssertFalse(compiled.findings.contains { $0.code == "output-reference-unresolved" }, "A blank site's references resolve")
        let blank = StaticBuildCompiler.compile(document: ProjectCreation.blank(), profileSelection: .init(profile: .development),
                                                resourceDescriptors: [:], resourceData: [:])
        XCTAssertFalse(blank.findings.contains { $0.code == "assets-unused" })
    }

    // SF-1208-001/003/004/008, SF-1211-001/003/004 (OD-042, ADR-0122): saved build
    // settings resolve with provenance, the per-file report totals every written
    // file, budgets produce warnings that name the output (and the object that shows
    // it), and the release policy decides whether warnings block Static Release.
    func testBuildSettingsResolveBudgetsPerFileReportAndReleasePolicy() throws {
        // Resolution: omitted → SiteForge default; authored wins; an invalid stored value is kept but not used.
        XCTAssertEqual(BuildSettingsResolver.profile(nil).value, .development)
        XCTAssertEqual(BuildSettingsResolver.profile(nil).source, .builtIn)
        XCTAssertEqual(BuildSettingsResolver.profile(BuildProfileSettings(profile: .staticRelease)).source, .project)
        XCTAssertEqual(BuildSettingsResolver.budget(.page, nil).value, BuildProfileSettings.defaultPageBudgetKilobytes)
        XCTAssertEqual(BuildSettingsResolver.budget(.page, BuildProfileSettings(pageBudgetKilobytes: 0)).value, 0)
        XCTAssertEqual(BuildSettingsResolver.budget(.page, BuildProfileSettings(pageBudgetKilobytes: 0)).source, .project)
        let damagedBudget = BuildSettingsResolver.budget(.asset, BuildProfileSettings(assetBudgetKilobytes: -5))
        XCTAssertEqual(damagedBudget.value, BuildProfileSettings.defaultAssetBudgetKilobytes)
        XCTAssertEqual(damagedBudget.source, .invalidProjectValue)
        XCTAssertEqual(BuildSettingsResolver.releasePolicy(nil).value, .errorsOnly)
        XCTAssertEqual(BuildProfileSettings(assetBudgetKilobytes: -5).invalidSettingIDs, [.assetBudget])
        XCTAssertTrue(BuildProfileSettings(assetBudgetKilobytes: -5).isStructurallyValid, "Recoverable, not corrupt")
        XCTAssertFalse(BuildProfileSettings(assetBudgetKilobytes: -5).isValid)
        XCTAssertTrue(BuildProfileSettings().isEmpty)
        XCTAssertEqual(BuildProfileSettings(profile: .staticRelease, releasePolicy: .warningsBlockRelease)
            .changedSettingIDs(from: nil), [.profile, .releasePolicy])
        XCTAssertTrue(BuildProfileSettings(assetBudgetKilobytes: -5).introducesInvalidBudget(comparedWith: nil))
        XCTAssertFalse(BuildProfileSettings(assetBudgetKilobytes: -5, releasePolicy: .errorsOnly)
            .introducesInvalidBudget(comparedWith: BuildProfileSettings(assetBudgetKilobytes: -5)),
            "An untouched stored value is retained")
        XCTAssertEqual(BuildProfileSettings.budgetChoices(.page, including: 300).filter { $0 == 300 }.count, 1)
        XCTAssertEqual(BuildSettingsResolver.budgetLabel(0), "No limit")
        XCTAssertEqual(BuildSettingsResolver.budgetLabel(2_048), "2 MB")
        XCTAssertEqual(BuildSettingsResolver.budgetLabel(300), "300 KB")

        // Versioned, strict serialization: unset values are omitted, never null.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let settings = BuildProfileSettings(profile: .staticRelease, pageBudgetKilobytes: 0, releasePolicy: .warningsBlockRelease)
        let settingsData = try encoder.encode(settings)
        XCTAssertEqual(String(decoding: settingsData, as: UTF8.self),
            "{\"pageBudgetKilobytes\":0,\"profile\":\"staticRelease\",\"releasePolicy\":\"warnings-block-release\",\"version\":1}")
        XCTAssertEqual(try JSONDecoder().decode(BuildProfileSettings.self, from: settingsData), settings)
        for damaged in ["{\"version\":2}", "{\"version\":1,\"profile\":null}", "{\"version\":1,\"extra\":1}",
                        "{\"version\":1,\"profile\":\"staging\"}", "{\"profile\":\"development\"}"] {
            XCTAssertThrowsError(try JSONDecoder().decode(BuildProfileSettings.self, from: Data(damaged.utf8)), damaged)
        }
        let preferences = ProjectPreferences(build: settings)
        XCTAssertEqual(try JSONDecoder().decode(ProjectPreferences.self, from: try encoder.encode(preferences)), preferences)
        XCTAssertFalse(preferences.isEmpty)
        XCTAssertFalse(ProjectPreferences(build: BuildProfileSettings()).isStructurallyValid, "An empty build record is never stored")
        XCTAssertThrowsError(try JSONDecoder().decode(ProjectPreferences.self, from: Data("{\"version\":1,\"build\":null}".utf8)))
        XCTAssertFalse(String(decoding: try encoder.encode(ProjectPreferences(gridSpacing: 24)), as: UTF8.self).contains("build"))

        // Per-file report: sorted rows, kinds, cache policy, totals by kind and budget flags.
        let hash = String(repeating: "c", count: 64)
        let records = [
            StaticOutputFileRecord(path: "index.html", bytes: 300 * 1_024, sha256: hash, cache: .revalidate),
            StaticOutputFileRecord(path: "assets/\(hash).png", bytes: 6 * 1_024 * 1_024, sha256: hash, cache: .immutable),
            StaticOutputFileRecord(path: "styles.css", bytes: 2_000, sha256: hash, cache: .revalidate),
            StaticOutputFileRecord(path: "about.html", bytes: 1_000, sha256: hash, cache: .revalidate),
        ]
        let defaults = BuildSettingsResolution(nil)
        let summary = StaticBuildOutputSummary(files: records, settings: defaults)
        XCTAssertEqual(summary.rows.map(\.path), ["about.html", "assets/\(hash).png", "index.html", "styles.css"])
        XCTAssertEqual(summary.rows.map(\.kind), [.page, .asset, .page, .stylesheet])
        XCTAssertEqual(summary.rows.map(\.cache), [.revalidate, .immutable, .revalidate, .revalidate])
        XCTAssertEqual(summary.rows.map(\.exceedsBudget), [false, true, true, false])
        XCTAssertEqual(summary.totals.map(\.kind), [.page, .stylesheet, .asset])
        XCTAssertEqual(summary.totals.map(\.count), [2, 1, 1])
        XCTAssertEqual(summary.totalBytes, 300 * 1_024 + 6 * 1_024 * 1_024 + 3_000)
        XCTAssertFalse(summary.totalExceedsBudget)
        XCTAssertEqual(summary.kilobytesToFit(.page), 300)
        XCTAssertEqual(summary.kilobytesToFit(.asset), 6_144)
        XCTAssertNil(summary.kilobytesToFit(.total))
        XCTAssertEqual(StaticBuildOutputSummary.fittingKilobytes(1), 1)
        XCTAssertEqual(StaticBuildOutputSummary.fittingKilobytes(1_025), 2)
        XCTAssertEqual(StaticOutputFileKind.kind(for: "fr/index.html"), .page)
        XCTAssertEqual(StaticOutputFileKind.kind(for: "siteforge-runtime.js"), .script)
        XCTAssertEqual(StaticOutputFileKind.kind(for: "sitemap.xml"), .siteFile)
        let unlimited = StaticBuildOutputSummary(files: records, settings: BuildSettingsResolution(
            BuildProfileSettings(pageBudgetKilobytes: 0, assetBudgetKilobytes: 0, totalBudgetKilobytes: 1)))
        XCTAssertEqual(unlimited.rows.map(\.exceedsBudget), [false, false, false, false], "0 is no limit")
        XCTAssertTrue(unlimited.totalExceedsBudget)

        // Budget findings are warnings that name the output and, for assets, the object.
        let imageNodeID = NodeID()
        let budgetFindings = StaticBuildBudgetAudit.findings(summary: summary, settings: defaults,
                                                             affectedNodes: ["assets/\(hash).png": imageNodeID])
        XCTAssertEqual(budgetFindings.map(\.code), ["budget-asset-exceeded", "budget-page-exceeded"])
        XCTAssertEqual(budgetFindings.map(\.outputPath), ["assets/\(hash).png", "index.html"])
        XCTAssertEqual(budgetFindings.first?.affectedNodeID, imageNodeID)
        XCTAssertTrue(budgetFindings.allSatisfy { $0.severity == .warning && $0.requirementID == "SF-1211-003" })
        XCTAssertEqual(StaticBuildBudgetAudit.findings(summary: unlimited, settings: defaults).map(\.code),
                       ["budget-total-exceeded"], "Per-file flags come from the summary's own settings")

        // Release policy: only Static Release under the stricter policy is blocked, and only by warnings.
        let strict = BuildSettingsResolution(BuildProfileSettings(releasePolicy: .warningsBlockRelease))
        XCTAssertTrue(strict.warningsBlock(.staticRelease))
        XCTAssertFalse(strict.warningsBlock(.development), "Development is never blocked by warnings")
        XCTAssertFalse(defaults.warningsBlock(.staticRelease))
        let blocked = try XCTUnwrap(StaticBuildBudgetAudit.releasePolicyFinding(findings: budgetFindings,
                                                                                profile: .staticRelease, settings: strict))
        XCTAssertEqual(blocked.severity, .error)
        XCTAssertNil(StaticBuildBudgetAudit.releasePolicyFinding(findings: [], profile: .staticRelease, settings: strict))
        XCTAssertNil(StaticBuildBudgetAudit.releasePolicyFinding(findings: budgetFindings, profile: .development, settings: strict))

        // Repair actions: raise the budget just enough, allow warnings, or check with Development.
        let report = LocalBuildReport(revision: 1, profile: .staticRelease, filePaths: records.map(\.path).sorted(),
                                      deferredCapabilities: [], outputFiles: records)
        XCTAssertEqual(StaticBuildRepairAction.action(for: budgetFindings[1], report: report, settings: defaults,
                                                      profile: .staticRelease), .raiseBudget(.page, kilobytes: 300))
        XCTAssertEqual(StaticBuildRepairAction.action(for: budgetFindings[0], report: report, settings: defaults,
                                                      profile: .staticRelease), .raiseBudget(.asset, kilobytes: 6_144))
        XCTAssertNil(StaticBuildRepairAction.action(for: budgetFindings[1], report: nil, settings: defaults, profile: .staticRelease))
        XCTAssertEqual(StaticBuildRepairAction.action(for: blocked, report: report, settings: strict, profile: .staticRelease),
                       .allowWarnings)
        let skipped = StaticBuildFinding(severity: .warning, code: "css-optimization-skipped", requirementID: "SF-1204-004",
                                         outputPath: "styles.css", explanation: "Skipped.", repair: "None.")
        XCTAssertEqual(StaticBuildRepairAction.action(for: skipped, report: report, settings: defaults, profile: .staticRelease),
                       .useProfile(.development))
        XCTAssertNil(StaticBuildRepairAction.action(for: skipped, report: report, settings: defaults, profile: .development))

        // End to end: a 1 KB site budget is exceeded by any site. Static Release under the
        // stricter policy cannot write; Development can; output bytes never change.
        var document = ProjectCreation.blank()
        document.projectPreferences = ProjectPreferences(build: BuildProfileSettings(totalBudgetKilobytes: 1,
                                                                                     releasePolicy: .warningsBlockRelease))
        try document.validate()
        var plainDocument = document
        plainDocument.projectPreferences = nil
        let release = StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .staticRelease),
                                                  resourceDescriptors: [:], resourceData: [:])
        let releaseReport = try XCTUnwrap(release.report, "\(release.findings.map(\.code))")
        XCTAssertGreaterThan(releaseReport.outputFiles.reduce(0) { $0 + $1.bytes }, 1_024, "Precondition")
        XCTAssertTrue(release.findings.contains { $0.code == "budget-total-exceeded" && $0.severity == .warning })
        XCTAssertTrue(release.findings.contains { $0.code == "release-policy-warnings" && $0.severity == .error })
        XCTAssertFalse(release.canWrite)
        XCTAssertNotNil(release.plan, "The per-file report stays available while writing is blocked")
        let plainRelease = StaticBuildCompiler.compile(document: plainDocument, profileSelection: .init(profile: .staticRelease),
                                                       resourceDescriptors: [:], resourceData: [:])
        XCTAssertEqual(release.plan, plainRelease.plan, "Build settings never change output bytes")
        XCTAssertFalse(plainRelease.findings.contains { $0.code.hasPrefix("budget-") || $0.code == "release-policy-warnings" })
        let development = StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .development),
                                                      resourceDescriptors: [:], resourceData: [:])
        XCTAssertTrue(development.findings.contains { $0.code == "budget-total-exceeded" })
        XCTAssertFalse(development.findings.contains { $0.code == "release-policy-warnings" })
        XCTAssertTrue(development.canWrite)
        XCTAssertFalse(development.redactedSummary.contains(document.id.description), "No raw identifiers")
    }

    // SF-1205 / SF-1206-001/004 (OD-042, ADR-0124): Static Release writes the generated
    // runtime as one content-hashed file. Every page that used a runtime references it
    // from its own folder (language trees, collection item pages) and names the parts it
    // runs; nothing references a file the build does not write; the name follows the bytes.
    func testStaticReleaseWritesOneContentHashedRuntimeEveryPageReferences() throws {
        func tags(_ parts: [String], prefix: String) -> String {
            parts.map { StaticRuntimeBundle.sourceTag($0, prefix: prefix) }.joined()
        }
        let state = "<div hidden data-siteforge-state=\"[]\"></div>"
        let sources: [LocalStaticBuildPlan.File] = [
            .init(path: "siteforge-navigation.js", contents: ConnectedPageOutput.menuScript),
            .init(path: "siteforge-effects.js", contents: DecorativeEffectRuntime.javascript),
            .init(path: "siteforge-motion.js", contents: MotionRuntime.javascript),
            .init(path: "siteforge-events.js", contents: EventGraphRuntime.javascript),
        ]
        // The planner's exact tags: menu, Flow and motion first, then the state and the interactions.
        let pages: [LocalStaticBuildPlan.File] = [
            .init(path: "index.html", contents: "<!doctype html><html><head><link rel=\"stylesheet\" href=\"styles.css\"></head><body><p>Home</p>\(tags(["navigation", "effects"], prefix: ""))</body></html>"),
            .init(path: "about.html", contents: "<!doctype html><html><head></head><body><p>About</p></body></html>"),
            .init(path: "posts/hello.html", contents: "<!doctype html><html><head><link rel=\"stylesheet\" href=\"../styles.css\"></head><body>\(tags(["motion"], prefix: "../"))\(state)\(tags(["events"], prefix: "../"))</body></html>"),
            .init(path: "fr/index.html", contents: "<!doctype html><html lang=\"fr\"><head></head><body>\(tags(["navigation", "effects"], prefix: "../"))</body></html>"),
            .init(path: "fr/posts/hello.html", contents: "<!doctype html><html lang=\"fr\"><head></head><body>\(tags(["motion"], prefix: "../../"))\(state)\(tags(["events"], prefix: "../../"))</body></html>"),
        ]
        let written = pages + sources + [LocalStaticBuildPlan.File(path: "styles.css", contents: ".a { color: red; }")]
        let plan = LocalStaticBuildPlan(revision: 4, files: written
            + [LocalStaticBuildPlan.File(path: "manifest.txt", contents: written.map(\.path).sorted().joined(separator: "\n"))])
        XCTAssertEqual(StaticOutputReferenceAudit.unresolved(in: plan), [:], "Precondition: the readable files resolve")

        let release = LocalBuildProfileCompiler.compile(plan, profile: .staticRelease)
        let runtimes = release.0.files.filter { StaticRuntimeBundle.isBundlePath($0.path) }
        XCTAssertEqual(runtimes.count, 1, "\(release.0.files.map(\.path))")
        let runtime = try XCTUnwrap(runtimes.first)
        XCTAssertEqual(runtime.path, "siteforge-runtime.\(ProjectResourceStore.digest(Data(runtime.contents.utf8))).js")
        XCTAssertEqual(runtime.path, StaticRuntimeBundle.path(for: runtime.contents))
        for source in sources {
            XCTAssertTrue(runtime.contents.contains(source.contents), source.path)
            XCTAssertFalse(release.0.files.contains { $0.path == source.path || $0.contents.contains(source.path) }, source.path)
        }
        for part in StaticRuntimeBundle.parts { XCTAssertTrue(runtime.contents.contains("run('\(part)', () => {"), part) }
        XCTAssertTrue(runtime.contents.contains("document.currentScript"))
        XCTAssertTrue(runtime.contents.contains("try { part(); } catch (error)"), "One failing part never stops another")

        func page(_ path: String) throws -> String {
            try XCTUnwrap(release.0.files.first { $0.path == path }?.contents, path)
        }
        XCTAssertTrue(try page("index.html").contains("<p>Home</p><script src=\"\(runtime.path)\" data-siteforge-runtime=\"navigation effects\" defer></script></body>"))
        XCTAssertTrue(try page("posts/hello.html").contains("<body><script src=\"../\(runtime.path)\" data-siteforge-runtime=\"motion events\" defer></script>\(state)</body>"))
        XCTAssertTrue(try page("fr/index.html").contains("<body><script src=\"../\(runtime.path)\" data-siteforge-runtime=\"navigation effects\" defer></script></body>"))
        XCTAssertTrue(try page("fr/posts/hello.html").contains("<body><script src=\"../../\(runtime.path)\" data-siteforge-runtime=\"motion events\" defer></script>\(state)</body>"))
        for path in ["index.html", "posts/hello.html", "fr/index.html", "fr/posts/hello.html"] {
            XCTAssertEqual(try page(path).components(separatedBy: runtime.path).count - 1, 1, path)
        }
        XCTAssertEqual(try page("about.html"), pages[1].contents, "A page without a runtime is unchanged")
        XCTAssertEqual(StaticOutputReferenceAudit.unresolved(in: release.0), [:], "Nothing references a file the build does not write")

        // Listed in manifest.txt, the integrity manifest and the report, cached as immutable.
        let listed = try page("manifest.txt").split(separator: "\n").map(String.init)
        XCTAssertTrue(listed.contains(runtime.path), "\(listed)")
        XCTAssertFalse(listed.contains { $0.hasPrefix("siteforge-") && !StaticRuntimeBundle.isBundlePath($0) }, "\(listed)")
        XCTAssertEqual(listed, listed.sorted())
        let record = try XCTUnwrap(release.1.outputFiles.first { $0.path == runtime.path })
        XCTAssertEqual(record.cache, .immutable)
        XCTAssertEqual(record.sha256, ProjectResourceStore.digest(Data(runtime.contents.utf8)))
        XCTAssertEqual(StaticOutputFileKind.kind(for: runtime.path), .script)
        let integrity = try JSONDecoder().decode(StaticOutputManifest.self, from: Data(page(StaticOutputManifest.fileName).utf8))
        XCTAssertEqual(integrity.files.first { $0.path == runtime.path }?.cache, .immutable)
        XCTAssertFalse(integrity.files.contains { file in sources.contains { $0.path == file.path } })
        XCTAssertEqual(StaticOutputCachePolicy.policy(for: "siteforge-events.js"), .revalidate)
        XCTAssertEqual(StaticOutputCachePolicy.policy(for: "siteforge-runtime.js"), .revalidate)
        XCTAssertEqual(StaticOutputCachePolicy.policy(for: "fr/" + runtime.path), .revalidate)

        // Identical input keeps the name and bytes; one changed byte gives a new name.
        XCTAssertEqual(LocalBuildProfileCompiler.compile(plan, profile: .staticRelease).0, release.0)
        var changedFiles = plan.files
        let motionIndex = try XCTUnwrap(changedFiles.firstIndex { $0.path == "siteforge-motion.js" })
        changedFiles[motionIndex] = LocalStaticBuildPlan.File(path: "siteforge-motion.js", contents: MotionRuntime.javascript + "\n")
        let changed = LocalBuildProfileCompiler.compile(LocalStaticBuildPlan(revision: 4, files: changedFiles), profile: .staticRelease).0
        let changedRuntime = try XCTUnwrap(changed.files.first { StaticRuntimeBundle.isBundlePath($0.path) })
        XCTAssertNotEqual(changedRuntime.path, runtime.path)
        XCTAssertTrue(try XCTUnwrap(changed.files.first { $0.path == "fr/posts/hello.html" }?.contents)
            .contains("src=\"../../\(changedRuntime.path)\""))
        XCTAssertEqual(StaticOutputReferenceAudit.unresolved(in: changed), [:])

        // A site with fewer runtimes gets a bundle of only those parts; none leaves the plan unchanged.
        let menuOnly = LocalStaticBuildPlan(revision: 4, files: [pages[1], sources[0],
            LocalStaticBuildPlan.File(path: "index.html", contents: "<body>\(tags(["navigation"], prefix: ""))</body>")])
        let menuRelease = LocalBuildProfileCompiler.compile(menuOnly, profile: .staticRelease).0
        let menuRuntime = try XCTUnwrap(menuRelease.files.first { StaticRuntimeBundle.isBundlePath($0.path) })
        XCTAssertTrue(menuRuntime.contents.contains("run('navigation', () => {"))
        XCTAssertFalse(menuRuntime.contents.contains("run('effects'"))
        XCTAssertNotEqual(menuRuntime.path, runtime.path)
        XCTAssertEqual(StaticOutputReferenceAudit.unresolved(in: menuRelease), [:])
        XCTAssertEqual(StaticRuntimeBundle.bundle([pages[1]]), [pages[1]])

        // Development keeps the readable per-runtime files, exactly as planned.
        let development = LocalBuildProfileCompiler.compile(plan, profile: .development)
        XCTAssertEqual(development.0.files, plan.files.sorted { $0.path < $1.path })
        XCTAssertFalse(development.0.files.contains { StaticRuntimeBundle.isBundlePath($0.path) })
        XCTAssertTrue(development.1.outputFiles.filter { $0.path.hasSuffix(".js") }.allSatisfy { $0.cache == .revalidate })
    }

    // SF-1208-003/008, SF-1211-003/008 (OD-042, ADR-0123, OD-121): a check keeps the
    // build settings it used, compares both profiles file by file, reports what a
    // rebuild changes by each file's cache key, grades its output for every browser
    // target with the chosen degradations, and yields a value-free diagnostic.
    func testBuildProfileComparisonRebuildChangesBrowserSupportAndDiagnostics() throws {
        var document = ProjectCreation.blank()
        document.projectPreferences = ProjectPreferences(build: BuildProfileSettings(pageBudgetKilobytes: 128))
        try document.validate()
        let release = StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .staticRelease),
                                                  resourceDescriptors: [:], resourceData: [:])
        let releaseReport = try XCTUnwrap(release.report, "\(release.findings.map(\.code))")
        XCTAssertTrue(release.canWrite)
        XCTAssertEqual(release.buildSettings, BuildSettingsResolution(document: document), "The check keeps the settings it used")
        XCTAssertEqual(release.buildSettings?.pageBudget.value, 128)

        // Profile comparison: the same result from either profile; pages are identical,
        // only Static Release writes the integrity manifest.
        let development = StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .development),
                                                      resourceDescriptors: [:], resourceData: [:])
        let developmentReport = try XCTUnwrap(development.report)
        let comparison = try XCTUnwrap(release.profileComparison)
        XCTAssertEqual(development.profileComparison, comparison)
        XCTAssertEqual(comparison.developmentBytes, developmentReport.outputFiles.reduce(0) { $0 + $1.bytes })
        XCTAssertEqual(comparison.staticReleaseBytes, releaseReport.outputFiles.reduce(0) { $0 + $1.bytes })
        XCTAssertEqual(comparison.rows.first { $0.path == StaticOutputManifest.fileName }?.difference, .onlyStaticRelease)
        XCTAssertTrue(comparison.rows.filter { $0.path.hasSuffix(".html") }.allSatisfy { $0.difference == .identical })
        XCTAssertFalse(comparison.rows.filter { $0.path.hasSuffix(".html") }.isEmpty, "Precondition")

        let hash = String(repeating: "d", count: 64), otherHash = String(repeating: "e", count: 64)
        let before = [StaticOutputFileRecord(path: "index.html", bytes: 10, sha256: hash, cache: .revalidate),
                      StaticOutputFileRecord(path: "styles.css", bytes: 30, sha256: hash, cache: .revalidate),
                      StaticOutputFileRecord(path: "old.html", bytes: 5, sha256: hash, cache: .revalidate)]
        let after = [StaticOutputFileRecord(path: "index.html", bytes: 10, sha256: hash, cache: .revalidate),
                     StaticOutputFileRecord(path: "styles.css", bytes: 20, sha256: otherHash, cache: .revalidate),
                     StaticOutputFileRecord(path: StaticOutputManifest.fileName, bytes: 7, sha256: otherHash, cache: .revalidate)]
        let fixed = StaticBuildProfileComparison(development: before, staticRelease: after)
        XCTAssertEqual(fixed.rows.map(\.path), ["index.html", "old.html", StaticOutputManifest.fileName, "styles.css"])
        XCTAssertEqual(fixed.rows.map(\.difference), [.identical, .onlyDevelopment, .onlyStaticRelease, .changed])
        XCTAssertEqual(fixed.rows.map(\.developmentBytes), [10, 5, nil, 30])
        XCTAssertEqual(fixed.differingRows.map(\.path), ["old.html", StaticOutputManifest.fileName, "styles.css"])
        XCTAssertEqual(fixed.developmentBytes, 45)
        XCTAssertEqual(fixed.staticReleaseBytes, 37)
        XCTAssertTrue(fixed.summary.contains("3 file(s) differ, 1 identical."), fixed.summary)
        XCTAssertFalse(fixed.summary.contains(hash), "Sizes and counts only")

        // Rebuild changes: each file's SHA-256 is its cache key.
        let changes = StaticOutputChangeSummary(previous: before, current: after)
        XCTAssertEqual(changes.added, [StaticOutputManifest.fileName])
        XCTAssertEqual(changes.changed, ["styles.css"])
        XCTAssertEqual(changes.removed, ["old.html"])
        XCTAssertEqual(changes.unchangedCount, 1)
        XCTAssertFalse(changes.isUnchanged)
        XCTAssertEqual(changes.summary, "Since the previous check: 1 changed, 1 added, 1 removed, 1 unchanged.")
        let again = StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .staticRelease),
                                                resourceDescriptors: [:], resourceData: [:])
        let unchanged = StaticOutputChangeSummary(previous: releaseReport.outputFiles, current: try XCTUnwrap(again.report).outputFiles)
        XCTAssertTrue(unchanged.isUnchanged, "An unchanged project rebuilds byte for byte")
        XCTAssertEqual(unchanged.unchangedCount, releaseReport.outputFiles.count)
        var grown = document
        grown.pages.append(DocumentPage(name: "About", route: .init(rawValue: "/about")))
        try grown.validate()
        let grownRelease = StaticBuildCompiler.compile(document: grown, profileSelection: .init(profile: .staticRelease),
                                                       resourceDescriptors: [:], resourceData: [:])
        let grownChanges = StaticOutputChangeSummary(previous: releaseReport.outputFiles,
                                                     current: try XCTUnwrap(grownRelease.report).outputFiles)
        XCTAssertTrue(grownChanges.added.contains("about.html"), "\(grownChanges.added)")
        XCTAssertEqual(grownChanges.removed, [])
        XCTAssertTrue(grownChanges.changed.contains(StaticOutputManifest.fileName), "The manifest lists the new page")

        // Browser target matrix (OD-121 default targets): each used feature is graded per
        // target; a target that predates a feature gets the generator's written fallback.
        let supportPlan = LocalStaticBuildPlan(revision: 1, files: [
            .init(path: "index.html", contents: "<details class=\"sf-nav-menu\"></details>"),
            .init(path: "styles.css", contents: "@container (min-width: 600px){.a{color:red}}@supports selector(details::details-content){.sf-nav-menu[open]::details-content{margin:0}}"),
            .init(path: "siteforge-motion.js", contents: "new IntersectionObserver(function () {})"),
        ])
        let support = StaticBrowserSupportReport(plan: supportPlan)
        XCTAssertEqual(support.targets, StaticBrowserTarget.allCases)
        XCTAssertEqual(support.entries.map(\.feature), [.containerQueries, .menuPanelLayout, .revealOnScroll])
        XCTAssertEqual(support.entries.first { $0.feature == .menuPanelLayout }?.degradedTargets, StaticBrowserTarget.allCases,
                       "Every default target predates ::details-content, so the fallback panel is used")
        XCTAssertEqual(support.entries.first { $0.feature == .containerQueries }?.degradedTargets, [])
        XCTAssertEqual(support.entries.first { $0.feature == .revealOnScroll }?.degradedTargets, [])
        XCTAssertEqual(support.grade(for: .safari), .degraded)
        XCTAssertEqual(support.targetSummary(.safari), "Safari 17: Works, with fallbacks")
        XCTAssertTrue(support.summary.contains("nothing stops working"), support.summary)
        XCTAssertEqual(StaticOutputFeature.menuPanelLayout.firstSupportedVersion(.safari).label, "18.4")
        XCTAssertTrue(StaticBrowserVersion(18, 4) > StaticBrowserVersion(18))
        XCTAssertTrue(StaticBrowserVersion(17) < StaticBrowserVersion(120))
        let plainSupport = StaticBrowserSupportReport(plan: LocalStaticBuildPlan(revision: 1, files: [
            .init(path: "index.html", contents: "<p>IntersectionObserver @container</p>")]))
        XCTAssertEqual(plainSupport.entries, [], "Page text is never read as a generated feature")
        XCTAssertEqual(plainSupport.grade(for: .firefox), .full)
        XCTAssertEqual(release.browserSupport, StaticBrowserSupportReport(plan: try XCTUnwrap(release.plan)))

        // Diagnostics: requirement IDs, sanitized identity, counts, duration, category; no values.
        let diagnostic = StaticOutputDiagnostic(compilation: release, durationMilliseconds: 12)
        XCTAssertEqual(diagnostic.requirementIDs, ["SF-1204-008", "SF-1206-008", "SF-1208-008", "SF-1211-008"])
        XCTAssertEqual(diagnostic.operation, "preflight")
        XCTAssertEqual(diagnostic.profile, "staticRelease")
        XCTAssertEqual(diagnostic.fileCount, releaseReport.outputFiles.count)
        XCTAssertEqual(diagnostic.totalBytes, comparison.staticReleaseBytes)
        XCTAssertEqual(diagnostic.durationMilliseconds, 12)
        XCTAssertEqual(diagnostic.failureCategory, "none")
        XCTAssertFalse(diagnostic.sanitizedDocumentID.contains(document.id.description))
        let cancelled = StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .development),
                                                    resourceDescriptors: [:], resourceData: [:], cancelled: true)
        XCTAssertEqual(StaticOutputDiagnostic(compilation: cancelled, durationMilliseconds: -3).failureCategory, "cancelled")
        XCTAssertEqual(StaticOutputDiagnostic(compilation: cancelled, durationMilliseconds: -3).durationMilliseconds, 0)
        XCTAssertNil(cancelled.profileComparison)
        XCTAssertNil(cancelled.buildSettings)
        XCTAssertNil(cancelled.browserSupport)
    }

    // SF-1204-007 / SF-1206-007 / SF-1208-007 / SF-1211-007 (ADR-0120–ADR-0123): the
    // Static Release optimizer, the reference audit, the per-file report, the profile
    // comparison and the rebuild change summary stay within safety bounds on the
    // standard (100 objects) and large (10,000 objects) fixtures; so does the Static Release
    // runtime bundle (SF-1205-007, ADR-0124) for a page per object.
    func testStaticOutputReportsStayWithinBoundsOnStandardAndLargeFixtures() throws {
        executionTimeAllowance = 120
        continueAfterFailure = false
        let clock = ContinuousClock()
        for (count, bound) in [(100, Duration.seconds(10)), (10_000, .seconds(60))] {
            let ids = (0..<count).map { _ in NodeID().rawValue.uuidString.lowercased() }
            let css = ids.map { "[data-siteforge-node=\"\($0)\"] { left: 1px; top: 2px; }" }.joined(separator: "\n")
                + "\n" + ids.prefix(count / 2).map { "@media (width < 600px) { [data-siteforge-node=\"\($0)\"] { left: 0; } }" }
                    .joined(separator: "\n")
            let html = ids.prefix(count / 2).map { "<div data-siteforge-node=\"\($0)\"></div>" }.joined()
            let records = ids.enumerated().map { index, id in
                StaticOutputFileRecord(path: "pages/\(id).html", bytes: index, sha256: id, cache: .revalidate)
            }
            let started = clock.now
            let optimized = StaticCSSOptimizer.optimize(css, usedIdentifiers: StaticCSSOptimizer.usedIdentifiers(in: [html]))
            let plan = LocalStaticBuildPlan(revision: 1, files: [.init(path: "index.html", contents: html),
                                                                 .init(path: "styles.css", contents: optimized.css)])
            let unresolved = StaticOutputReferenceAudit.unresolved(in: plan)
            let summary = StaticBuildOutputSummary(files: records, settings: BuildSettingsResolution(nil))
            let comparison = StaticBuildProfileComparison(development: records, staticRelease: Array(records.dropLast()))
            let changes = StaticOutputChangeSummary(previous: records, current: Array(records.dropFirst()))
            // SF-1205-007 (ADR-0124): one runtime file for a page per object, each in a folder.
            let runtimePages = ids.map { id in
                LocalStaticBuildPlan.File(path: "posts/\(id).html", contents: "<body>\(StaticRuntimeBundle.sourceTag("events", prefix: "../"))</body>")
            }
            let bundled = StaticRuntimeBundle.bundle(runtimePages
                + [LocalStaticBuildPlan.File(path: "siteforge-events.js", contents: EventGraphRuntime.javascript)])
            XCTAssertLessThan(started.duration(to: clock.now), bound, "\(count) objects: safety bound only")
            XCTAssertTrue(optimized.report.isOptimized, optimized.report.skippedReason ?? "")
            XCTAssertEqual(optimized.report.removedUnusedRules, count - count / 2, "Rules for objects no page contains")
            XCTAssertEqual(unresolved, [:])
            XCTAssertEqual(summary.rows.count, count)
            XCTAssertEqual(comparison.differingRows.count, 1)
            XCTAssertEqual(changes.removed.count, 1)
            XCTAssertEqual(changes.unchangedCount, count - 1)
            XCTAssertEqual(bundled.count, count + 1)
            let bundlePath = try XCTUnwrap(bundled.last?.path)
            XCTAssertTrue(StaticRuntimeBundle.isBundlePath(bundlePath))
            XCTAssertTrue(bundled.dropLast().allSatisfy { $0.contents.contains("src=\"../\(bundlePath)\" data-siteforge-runtime=\"events\"") })
        }
    }

    // SF-1207-001/003/004: with a site address and social image, each page's
    // head has search and Open Graph / Twitter tags with absolute URLs (the
    // image at its exported content-addressed path); robots.txt follows the
    // indexing preference and points at sitemap.xml, which lists only
    // indexable pages. Without an address, URL-only tags are omitted, the
    // canonical link stays the route, and no sitemap is written. Search
    // problems are reported as warnings that do not block export.
    func testSocialPreviewTagsSitemapRobotsAndSEOWarningsInExport() throws {
        let bytes = Data("social-image".utf8)
        let hash = ProjectResourceStore.digest(bytes)
        let resourceID = ResourceID()
        let asset = ImageAsset(resourceID: resourceID, displayName: "Share", originalFilename: "share.png",
            format: .png, pixelWidth: 1200, pixelHeight: 630, byteCount: bytes.count, contentHash: hash)
        var document = ProjectCreation.blank()
        document.imageAssets = [asset]
        let about = DocumentPage(name: "About", route: .init(rawValue: "/about"))
        let hidden = DocumentPage(name: "Drafts", route: .init(rawValue: "/drafts"))
        document.pages += [about, hidden]
        document.websiteMetadata = WebsiteMetadata(siteName: "Studio", defaultDescription: "Handmade things",
            pages: [PageWebsiteMetadata(pageID: hidden.id, allowsIndexing: false),
                    PageWebsiteMetadata(pageID: about.id, title: String(repeating: "Long title ", count: 8).trimmingCharacters(in: .whitespaces))],
            siteURL: "https://studio.example", socialImageAssetID: asset.id)
        try document.validate()
        let descriptor = ProjectResourceDescriptor(id: resourceID, filename: "share.png", mediaType: "image/png",
                                                   byteCount: bytes.count, sha256: hash)
        let compilation = StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .development),
            resourceDescriptors: [resourceID: descriptor], resourceData: [resourceID: bytes])
        let plan = try XCTUnwrap(compilation.plan, "\(compilation.findings.map(\.code))")
        XCTAssertEqual(plan.binaryFiles.map(\.path), ["assets/\(hash).png"], "The social image is exported")
        func file(_ path: String) throws -> String { try XCTUnwrap(plan.files.first { $0.path == path }?.contents, path) }
        let aboutHTML = try file("about.html")
        XCTAssertTrue(aboutHTML.contains("<link rel=\"canonical\" href=\"https://studio.example/about\">"))
        XCTAssertTrue(aboutHTML.contains("<meta property=\"og:url\" content=\"https://studio.example/about\">"))
        XCTAssertTrue(aboutHTML.contains("<meta property=\"og:site_name\" content=\"Studio\">"))
        XCTAssertTrue(aboutHTML.contains("<meta property=\"og:description\" content=\"Handmade things\">"))
        XCTAssertTrue(aboutHTML.contains("<meta property=\"og:image\" content=\"https://studio.example/assets/\(hash).png\">"))
        XCTAssertTrue(aboutHTML.contains("<meta name=\"twitter:card\" content=\"summary_large_image\">"))
        XCTAssertEqual(try file("robots.txt"), "User-agent: *\nAllow: /\nSitemap: https://studio.example/sitemap.xml\n")
        let sitemap = try file("sitemap.xml")
        XCTAssertTrue(sitemap.contains("<loc>https://studio.example/</loc>"))
        XCTAssertTrue(sitemap.contains("<loc>https://studio.example/about</loc>"))
        XCTAssertFalse(sitemap.contains("/drafts"), "Pages that discourage indexing are left out")
        XCTAssertFalse(sitemap.contains("/404"), "The Not Found page is left out")
        XCTAssertTrue(compilation.canWrite)
        let codes = compilation.findings.map(\.code)
        XCTAssertTrue(codes.contains("seo-title-long"))
        XCTAssertFalse(codes.contains("seo-description-missing"), "The default description applies")
        XCTAssertFalse(compilation.redactedSummary.contains("Long title"), "Findings carry no authored text")

        // Without a site address.
        var local = document
        local.websiteMetadata?.siteURL = nil
        let localCompilation = StaticBuildCompiler.compile(document: local, profileSelection: .init(profile: .development),
            resourceDescriptors: [resourceID: descriptor], resourceData: [resourceID: bytes])
        let localPlan = try XCTUnwrap(localCompilation.plan)
        let localHTML = try XCTUnwrap(localPlan.files.first { $0.path == "about.html" }?.contents)
        XCTAssertTrue(localHTML.contains("<link rel=\"canonical\" href=\"/about\">"))
        XCTAssertFalse(localHTML.contains("og:url"))
        XCTAssertFalse(localHTML.contains("og:image"))
        XCTAssertTrue(localHTML.contains("<meta name=\"twitter:card\" content=\"summary\">"))
        XCTAssertNil(localPlan.files.first { $0.path == "sitemap.xml" })
        XCTAssertEqual(localPlan.files.first { $0.path == "robots.txt" }?.contents, "User-agent: *\nAllow: /\n")
        XCTAssertTrue(localCompilation.findings.contains { $0.code == "seo-social-image-needs-site-url" })

        // Duplicate titles and a site that discourages indexing.
        var duplicate = local
        XCTAssertEqual(StaticSEOEmitter.robots(allowsIndexing: false, siteURL: "https://studio.example"), "User-agent: *\nDisallow: /\n")
        duplicate.websiteMetadata = WebsiteMetadata(siteName: "Studio", titlePattern: "{site}")
        let duplicateCodes = StaticSEOAudit.findings(document: duplicate).map(\.code)
        XCTAssertEqual(duplicateCodes.filter { $0 == "seo-title-duplicate" }.count, 3, "Home, About and Drafts share the title")
        XCTAssertEqual(duplicateCodes.filter { $0 == "seo-description-missing" }.count, 3)
    }

    // SF-1207-003/004, SF-1003 (ADR-0144): search warnings check the pages a
    // build writes. Item pages take their title from their item, so two
    // items with one title are reported at their own addresses; the template
    // page, which is never written, is not checked.
    func testSEOWarningsCheckCollectionItemPagesNotTheTemplate() throws {
        var document = ProjectCreation.blank()
        let template = DocumentPage(name: "Post", route: .init(rawValue: "/post"))
        document.pages.append(template)
        let title = CollectionField(key: "title", label: "Title", type: .text)
        func item(_ slug: String) -> CollectionItem {
            CollectionItem(slug: slug, status: .published, values: [.init(fieldID: title.id, value: .text("Same title"))])
        }
        document.collections = [ContentCollection(name: "Posts", slug: "blog", fields: [title],
            items: [item("first"), item("second")], template: CollectionTemplate(pageID: template.id))]
        document.websiteMetadata = WebsiteMetadata(siteName: "Studio", defaultDescription: "Handmade things")
        try document.validate()
        let findings = StaticSEOAudit.findings(document: document)
        XCTAssertEqual(findings.filter { $0.code == "seo-title-duplicate" }.compactMap(\.outputPath), ["/blog/first", "/blog/second"])
        XCTAssertFalse(findings.contains { $0.outputPath == "/post" }, "The template page is not written")
    }

    // OD-144 (ADR-0144, lane V16): with a site address every written page has
    // exactly one schema.org JSON-LD block in its head, built only from typed
    // metadata: a WebPage (title, description, absolute address, language)
    // that is part of the WebSite, which the home page also describes. The
    // Not Found page and a site without an address get none. Output is
    // deterministic, Static Release writes the page unchanged, and the
    // integrity manifest hashes the page with its block.
    func testStructuredDataDescribesEachPageOnlyWithASiteAddress() throws {
        var document = ProjectCreation.blank()
        let about = DocumentPage(name: "About", route: .init(rawValue: "/about"))
        document.pages.append(about)
        document.websiteMetadata = WebsiteMetadata(siteName: "Studio", defaultDescription: "Handmade things",
                                                   siteURL: "https://studio.example")
        try document.validate()
        let home = try XCTUnwrap(document.pages.first { $0.role == .home })
        let homeTitle = WebsiteMetadataResolver.resolve(page: home, document: document).title
        let aboutTitle = WebsiteMetadataResolver.resolve(page: about, document: document).title
        let plan = try MultiPageStaticBuildPlanner.plan(document: document)
        XCTAssertEqual(try MultiPageStaticBuildPlanner.plan(document: document), plan, "Deterministic")
        func file(_ path: String) throws -> String { try XCTUnwrap(plan.files.first { $0.path == path }?.contents, path) }
        let aboutPage = "{\"@type\":\"WebPage\",\"@id\":\"https://studio.example/about#webpage\",\"url\":\"https://studio.example/about\","
            + "\"name\":\"\(StaticSEOEmitter.jsonEscape(aboutTitle))\",\"description\":\"Handmade things\",\"inLanguage\":\"en\","
            + "\"isPartOf\":{\"@id\":\"https://studio.example/#website\"}}"
        let aboutHTML = try file("about.html")
        XCTAssertTrue(aboutHTML.contains("<script type=\"application/ld+json\">{\"@context\":\"https://schema.org\",\"@graph\":["
            + aboutPage + "]}</script>"), aboutHTML)
        let website = "{\"@type\":\"WebSite\",\"@id\":\"https://studio.example/#website\",\"url\":\"https://studio.example/\","
            + "\"name\":\"Studio\",\"inLanguage\":\"en\"}"
        let homeHTML = try file("index.html")
        XCTAssertTrue(homeHTML.contains("\"@graph\":[" + website + ",{\"@type\":\"WebPage\",\"@id\":\"https://studio.example/#webpage\","
            + "\"url\":\"https://studio.example/\",\"name\":\"\(StaticSEOEmitter.jsonEscape(homeTitle))\""), homeHTML)
        XCTAssertFalse(aboutHTML.contains("\"@type\":\"WebSite\""), "Only the home page describes the WebSite")
        for html in [homeHTML, aboutHTML] {
            XCTAssertEqual(html.components(separatedBy: "application/ld+json").count, 2, "One block per page")
            let block = try XCTUnwrap(html.range(of: "application/ld+json"))
            XCTAssertLessThan(block.upperBound, try XCTUnwrap(html.range(of: "</head>")).lowerBound, "The block is in the head")
        }
        XCTAssertFalse(try file("404.html").contains("application/ld+json"), "The Not Found page has none")

        // Static Release writes the page unchanged; the manifest hashes it with its block.
        let release = StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .staticRelease),
                                                  resourceDescriptors: [:], resourceData: [:])
        let releasePlan = try XCTUnwrap(release.plan, "\(release.findings.map(\.code))")
        let releaseAbout = try XCTUnwrap(releasePlan.files.first { $0.path == "about.html" }?.contents)
        XCTAssertTrue(releaseAbout.contains(aboutPage), releaseAbout)
        let record = try XCTUnwrap(release.report?.outputFiles.first { $0.path == "about.html" })
        XCTAssertEqual(record.sha256, ProjectResourceStore.digest(Data(releaseAbout.utf8)))

        // Without a site address nothing is written.
        var local = document
        local.websiteMetadata?.siteURL = nil
        let localPlan = try MultiPageStaticBuildPlanner.plan(document: local)
        XCTAssertFalse(localPlan.files.contains { $0.contents.contains("application/ld+json") })
    }

    // OD-144 (ADR-0144, lane V16): authored text is JSON-escaped and `<`, `>`,
    // `&` and the line separators become `\u` escapes, so a title can never
    // close the script element; the block is valid JSON with the exact text.
    func testStructuredDataEscapesTextSoItCannotCloseItsScript() throws {
        let hostile = StaticSEOMetadata(siteName: "A&B <Shop>", title: "</script><script>alert(1)</script>",
            description: "Line\u{2028}two \"quoted\" back\\slash\n<!-- c -->\u{1}", language: "en", index: true, follow: true)
        let block = StaticSEOEmitter.structuredData(hostile, route: "/about", siteRoot: "/", isHome: true,
                                                    siteURL: "https://studio.example")
        let prefix = "<script type=\"application/ld+json\">", suffix = "</script>"
        XCTAssertTrue(block.hasPrefix(prefix), block)
        XCTAssertTrue(block.hasSuffix(suffix), block)
        XCTAssertEqual(block.components(separatedBy: "</script").count, 2, "Only the block's own end tag")
        let json = String(block.dropFirst(prefix.count).dropLast(suffix.count))
        XCTAssertFalse(json.contains("<") || json.contains(">") || json.contains("&") || json.contains("\u{2028}"), json)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(object["@context"] as? String, "https://schema.org")
        let graph = try XCTUnwrap(object["@graph"] as? [[String: Any]])
        XCTAssertEqual(graph.map { $0["@type"] as? String }, ["WebSite", "WebPage"])
        XCTAssertEqual(graph[0]["name"] as? String, hostile.siteName)
        XCTAssertEqual(graph[1]["name"] as? String, hostile.title)
        XCTAssertEqual(graph[1]["description"] as? String, hostile.description)
        XCTAssertEqual(StaticSEOEmitter.jsonEscape("<&>\u{1}\u{2029}"), "\\u003c\\u0026\\u003e\\u0001\\u2029")
        XCTAssertEqual(StaticSEOEmitter.structuredData(hostile, route: "/about", siteRoot: "/", isHome: false, siteURL: nil), "")
    }

    // OD-144 (ADR-0144, lane V16): every language tree describes its own pages
    // at their localized addresses with its language, and its home page its
    // own WebSite; collection item pages (dynamic routes) are web pages at
    // their item addresses, and the template page, never written, has none.
    func testStructuredDataFollowsEveryLanguageTreeAndCollectionItemPages() throws {
        var document = ProjectCreation.blank()
        document.pages.append(DocumentPage(name: "About", route: .init(rawValue: "/about")))
        var localization = try SiteLocalizationEditing.start(code: "en", name: "English")
        _ = try SiteLocalizationEditing.addLocale(code: "fr", name: "Français", to: &localization)
        document.localization = localization
        document.websiteMetadata = WebsiteMetadata(siteName: "Studio", siteURL: "https://studio.example")
        try document.validate()
        let plan = try MultiPageStaticBuildPlanner.plan(document: document)
        func file(_ path: String) throws -> String { try XCTUnwrap(plan.files.first { $0.path == path }?.contents, path) }
        let frenchAbout = try file("fr/about.html")
        XCTAssertTrue(frenchAbout.contains("\"@id\":\"https://studio.example/fr/about#webpage\",\"url\":\"https://studio.example/fr/about\""), frenchAbout)
        XCTAssertTrue(frenchAbout.contains("\"inLanguage\":\"fr\",\"isPartOf\":{\"@id\":\"https://studio.example/fr/#website\"}"), frenchAbout)
        XCTAssertTrue(try file("fr/index.html").contains("{\"@type\":\"WebSite\",\"@id\":\"https://studio.example/fr/#website\","
            + "\"url\":\"https://studio.example/fr/\",\"name\":\"Studio\",\"inLanguage\":\"fr\"}"))
        let englishAbout = try file("about.html")
        XCTAssertTrue(englishAbout.contains("\"url\":\"https://studio.example/about\""), englishAbout)
        XCTAssertTrue(englishAbout.contains("\"inLanguage\":\"en\",\"isPartOf\":{\"@id\":\"https://studio.example/#website\"}"), englishAbout)
        XCTAssertFalse(try file("fr/404.html").contains("application/ld+json"))

        var site = ProjectCreation.blank()
        let template = DocumentPage(name: "Post", route: .init(rawValue: "/post"))
        site.pages.append(template)
        let title = CollectionField(key: "title", label: "Title", type: .text)
        func item(_ slug: String) -> CollectionItem {
            CollectionItem(slug: slug, status: .published, values: [.init(fieldID: title.id, value: .text("Post \(slug)"))])
        }
        site.collections = [ContentCollection(name: "Posts", slug: "blog", fields: [title],
            items: [item("first"), item("second")], template: CollectionTemplate(pageID: template.id))]
        site.websiteMetadata = WebsiteMetadata(siteName: "Studio", siteURL: "https://studio.example")
        try site.validate()
        let items = try MultiPageStaticBuildPlanner.plan(document: site)
        for slug in ["first", "second"] {
            let page = try XCTUnwrap(items.files.first { $0.contents.contains("\"url\":\"https://studio.example/blog/\(slug)\"") }, slug)
            XCTAssertEqual(page.contents.components(separatedBy: "application/ld+json").count, 2, "One block per item page")
        }
        XCTAssertFalse(items.files.contains { $0.contents.contains("\"url\":\"https://studio.example/post\"") },
                       "The template page is not written")
    }

    // SF-1206-003/004/008, SF-1208-004 — only referenced verified bytes enter
    // nested output; paths and orphaned resources never do.
    func testStaticBuildCompilerExportsOnlyReferencedVerifiedAssetsAndWriterContainsPaths() throws {
        let bytes = Data("verified-image".utf8)
        let hash = ProjectResourceStore.digest(bytes)
        let resourceID = ResourceID(), orphanID = ResourceID(), pageID = PageID(), nodeID = NodeID()
        let asset = ImageAsset(resourceID: resourceID, displayName: "Hero", originalFilename: "secret.png",
            format: .png, pixelWidth: 20, pixelHeight: 10, byteCount: bytes.count, contentHash: hash)
        let node = DocumentNode(id: nodeID, kind: .image, name: "Hero", parent: .page(pageID), properties: [
            .init(key: .init(rawValue: "layout.x"), value: .number(0), origin: .defaulted),
            .init(key: .init(rawValue: "layout.y"), value: .number(0), origin: .defaulted),
            .init(key: .init(rawValue: "layout.width"), value: .number(20), origin: .defaulted),
            .init(key: .init(rawValue: "layout.height"), value: .number(10), origin: .defaulted),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "assetID"), value: .string(asset.id.description), origin: .authored),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "fit"), value: .string(ImageFitMode.fit.rawValue), origin: .defaulted),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "focal.x"), value: .number(0.5), origin: .defaulted),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "focal.y"), value: .number(0.5), origin: .defaulted),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "alt"), value: .string("Hero"), origin: .authored),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "decorative"), value: .boolean(false), origin: .defaulted),
        ])
        let page = DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home,
                                rootNodeIDs: [nodeID], nodes: [node])
        let document = CanonicalDocument(pages: [page], imageAssets: [asset])
        let descriptor = ProjectResourceDescriptor(id: resourceID, filename: "secret.png", mediaType: "image/png",
                                                   byteCount: bytes.count, sha256: hash)
        let orphan = ProjectResourceDescriptor(id: orphanID, filename: "orphan.png", mediaType: "image/png",
                                               byteCount: bytes.count, sha256: hash)
        let compilation = StaticBuildCompiler.compile(document: document,
            profileSelection: .init(profile: .development),
            resourceDescriptors: [resourceID: descriptor, orphanID: orphan],
            resourceData: [resourceID: bytes, orphanID: bytes])
        let plan = try XCTUnwrap(compilation.plan)
        XCTAssertEqual(plan.binaryFiles.map(\.path), ["assets/\(hash).png"])
        XCTAssertFalse(plan.files.map(\.contents).joined().contains("secret.png"))
        XCTAssertFalse(plan.files.map(\.contents).joined().contains("orphan.png"))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent("site")
        try LocalStaticBuildWriter.write(plan, to: destination, expectedRevision: document.revision)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("assets/\(hash).png")), bytes)

        let unsafe = LocalStaticBuildPlan(revision: 1, files: [.init(path: "../escape", contents: "bad")])
        XCTAssertThrowsError(try LocalStaticBuildWriter.write(unsafe, to: root.appendingPathComponent("bad"), expectedRevision: 1))
    }

    // SF-AUTHORING-113, SF-0905-003/004/008, SF-1204-004/008 — static
    // output must fail closed when retained instance intent no longer has a
    // definition binding, without placing authored content in diagnostics.
    func testStaticBuildCompilerReportsRedactedComponentOverrideConflict() throws {
        let definitionID = PageID(), sourceID = NodeID(), pageID = PageID(), instanceID = NodeID()
        let missingBindingID = ComponentTextPropertyID()
        let definition = DocumentPage(id: definitionID, name: "Card", route: .init(rawValue: ""),
            role: .componentDefinition, provenance: .authored, rootNodeIDs: [sourceID], nodes: [
                DocumentNode(id: sourceID, kind: .frame, name: "Root", parent: .page(definitionID))
            ])
        let instance = DocumentNode(id: instanceID, kind: .component, name: "Card", parent: .page(pageID),
            properties: [
                .init(key: .init(rawValue: CanonicalComponentReference.key), value: .string(definitionID.description)),
                .init(key: .init(rawValue: CanonicalComponentText.overrideKey(missingBindingID)),
                      value: .string("Private retained content"), origin: .authored),
                .init(key: .init(rawValue: "layout.x"), value: .number(0), origin: .defaulted),
                .init(key: .init(rawValue: "layout.y"), value: .number(0), origin: .defaulted),
                .init(key: .init(rawValue: "layout.width"), value: .number(240), origin: .defaulted),
                .init(key: .init(rawValue: "layout.height"), value: .number(160), origin: .defaulted),
            ])
        let page = DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home,
            rootNodeIDs: [instanceID], nodes: [instance])
        let document = CanonicalDocument(pages: [page, definition])
        let result = StaticBuildCompiler.compile(document: document,
            profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:])
        XCTAssertNil(result.plan)
        XCTAssertEqual(result.findings.map(\.code), ["component-override-conflict"])
        XCTAssertFalse(result.redactedSummary.contains("Private retained content"))
        XCTAssertFalse(result.redactedSummary.contains(instanceID.description))
    }
    // SF-0802-001, SF-0802-004, SF-0802-008 — Fit/Fill/Stretch share one
    // top-left/Y-down geometry contract and focal points never change bounds.
    func testImageLayoutFitFillStretchFocalAndInvalidInputsAreDeterministic() throws {
        let bounds = WorldRect(
            origin: .init(x: 40, y: 60),
            size: .init(width: 320, height: 240)
        )
        XCTAssertEqual(CanvasImageLayout.destinationRect(
            source: .init(width: 1600, height: 900), bounds: bounds,
            mode: .fit, focalX: 0, focalY: 1
        ), WorldRect(origin: .init(x: 40, y: 90), size: .init(width: 320, height: 180)))
        XCTAssertEqual(CanvasImageLayout.destinationRect(
            source: .init(width: 1600, height: 900), bounds: bounds,
            mode: .stretch, focalX: 0.3, focalY: 0.7
        ), bounds)
        let leftFill = try XCTUnwrap(CanvasImageLayout.destinationRect(
            source: .init(width: 1600, height: 900), bounds: bounds,
            mode: .fill, focalX: 0, focalY: 0.5
        ))
        let rightFill = try XCTUnwrap(CanvasImageLayout.destinationRect(
            source: .init(width: 1600, height: 900), bounds: bounds,
            mode: .fill, focalX: 1, focalY: 0.5
        ))
        XCTAssertEqual(leftFill.size, rightFill.size)
        XCTAssertEqual(leftFill.origin.x, bounds.origin.x)
        XCTAssertLessThan(rightFill.origin.x, leftFill.origin.x)
        XCTAssertNil(CanvasImageLayout.destinationRect(
            source: .init(width: 0, height: 10), bounds: bounds,
            mode: .fit, focalX: 0.5, focalY: 0.5
        ))
        XCTAssertNil(CanvasImageLayout.destinationRect(
            source: .init(width: 10, height: 10), bounds: bounds,
            mode: .fill, focalX: .nan, focalY: 0.5
        ))
    }

    func testImageRenderPlanAdoptsImmutableBytesIdentityGeometryAndAccessibility() throws {
        let fixture = try makeFixture(count: 1)
        let bytes = Data([0x89, 0x50, 0x4e, 0x47])
        let assetID = AssetID()
        let object = CanvasRenderObject(
            id: fixture.scene.objects[0].id,
            frame: fixture.scene.objects[0].frame,
            clipRect: fixture.scene.objects[0].clipRect,
            paintOrder: 0, style: .imagePlaceholder, isVisible: true,
            accessibilityLabel: "Image, Product photo",
            displayName: "Product photo", imageAssetID: assetID,
            imageData: bytes, imagePixelWidth: 1600, imagePixelHeight: 900,
            imageFitMode: .fill, imageFocalX: 0.25, imageFocalY: 0.75
        )
        let scene = CanvasRenderSceneSnapshot(
            identity: fixture.scene.identity, surfaceID: fixture.scene.surfaceID,
            objects: [object]
        )
        let plan = try CanvasRendererCore().prepare(
            scene: scene,
            overlays: .init(identity: scene.identity, overlays: []),
            viewport: fixture.viewport
        )
        XCTAssertEqual(plan.authoredObjects.first, object)
        XCTAssertEqual(plan.accessibilityElements.first?.objectID, object.id)
        XCTAssertEqual(plan.accessibilityElements.first?.label, "Image, Product photo")
        XCTAssertEqual(CanvasRendererCore().hitTest(.init(x: 5, y: 5), in: plan), object.id)

        let changed = CanvasRenderSceneSnapshot(
            identity: scene.identity, surfaceID: scene.surfaceID,
            objects: [CanvasRenderObject(
                id: object.id, frame: object.frame, clipRect: object.clipRect,
                paintOrder: 0, style: .imagePlaceholder, isVisible: true,
                accessibilityLabel: object.accessibilityLabel,
                displayName: object.displayName, imageAssetID: assetID,
                imageData: Data([1, 2, 3]), imagePixelWidth: 1600,
                imagePixelHeight: 900, imageFitMode: .fit
            )]
        )
        XCTAssertNotEqual(
            plan.deterministicDigest,
            try CanvasRendererCore().prepare(
                scene: changed,
                overlays: .init(identity: changed.identity, overlays: []),
                viewport: fixture.viewport
            ).deterministicDigest
        )
    }

    // SF-0201-003, SF-0407-001, SF-0407-003
    func testExplicitBlankSceneAdoptsWithoutFabricatingRenderableObjects() throws {
        let fixture = try makeFixture(count: 1)
        let scene = CanvasRenderSceneSnapshot(
            identity: fixture.scene.identity,
            surfaceID: fixture.scene.surfaceID,
            objects: []
        )

        let plan = try CanvasRendererCore().prepare(
            scene: scene,
            overlays: .init(identity: scene.identity, overlays: []),
            viewport: fixture.viewport
        )

        XCTAssertTrue(plan.authoredObjects.isEmpty)
        XCTAssertTrue(plan.accessibilityElements.isEmpty)
        XCTAssertNil(CanvasRendererCore().hitTest(.init(x: 50, y: 50), in: plan))
        XCTAssertEqual(plan.deterministicDigest, try CanvasRendererCore().prepare(
            scene: scene,
            overlays: .init(identity: scene.identity, overlays: []),
            viewport: fixture.viewport
        ).deterministicDigest)
    }

    // SF-0407-001, SF-0407-003, SF-0407-008
    func testDeterministicPaintOrderAndReverseHitTesting() throws {
        let fixture = try makeFixture(count: 3, overlapping: true)
        let plan = try CanvasRendererCore().prepare(
            scene: fixture.scene,
            overlays: fixture.overlays,
            viewport: fixture.viewport
        )
        XCTAssertEqual(plan.authoredObjects.map(\.paintOrder), [0, 1, 2])
        XCTAssertEqual(
            CanvasRendererCore().hitTest(WorldPoint(x: 55, y: 55), in: plan),
            fixture.scene.objects[2].id
        )
        XCTAssertEqual(plan.deterministicDigest, try CanvasRendererCore().prepare(
            scene: fixture.scene,
            overlays: fixture.overlays,
            viewport: fixture.viewport
        ).deterministicDigest)
    }

    // SF-0407-003, SF-0407-004
    func testVisibilityAndClippingControlRenderingAndHitTesting() throws {
        let base = try makeFixture(count: 3, overlapping: true)
        let hidden = CanvasRenderObject(
            id: base.scene.objects[2].id,
            frame: base.scene.objects[2].frame,
            clipRect: base.scene.objects[2].clipRect,
            paintOrder: 2,
            style: .page,
            isVisible: false,
            accessibilityLabel: "Hidden"
        )
        let clipped = CanvasRenderObject(
            id: base.scene.objects[1].id,
            frame: base.scene.objects[1].frame,
            clipRect: WorldRect(origin: WorldPoint(x: 0, y: 0), size: WorldSize(width: 10, height: 10)),
            paintOrder: 1,
            style: .page,
            isVisible: true,
            accessibilityLabel: "Clipped"
        )
        let scene = CanvasRenderSceneSnapshot(
            identity: base.scene.identity,
            surfaceID: base.scene.surfaceID,
            objects: [base.scene.objects[0], clipped, hidden]
        )
        let plan = try CanvasRendererCore().prepare(scene: scene, overlays: base.overlays, viewport: base.viewport)
        XCTAssertEqual(CanvasRendererCore().hitTest(WorldPoint(x: 55, y: 55), in: plan), base.scene.objects[0].id)
        XCTAssertEqual(plan.accessibilityElements.map(\.objectID), [base.scene.objects[0].id])
    }

    // SF-0407-003, SF-0407-006 — VoiceOver geometry is the exact visible
    // object intersection, never the authored offscreen/ancestor-clipped box.
    func testAccessibilityFramesIntersectObjectClipAndVisibleViewport() throws {
        let fixture = try makeFixture(count: 1)
        let clipped = CanvasRenderObject(
            id: fixture.scene.objects[0].id,
            frame: WorldRect(
                origin: WorldPoint(x: -20, y: -10),
                size: WorldSize(width: 70, height: 60)
            ),
            clipRect: WorldRect(
                origin: WorldPoint(x: 0, y: 5),
                size: WorldSize(width: 30, height: 25)
            ),
            paintOrder: 0,
            style: .frameSurface,
            isVisible: true,
            accessibilityLabel: "Partially clipped frame"
        )
        let scene = CanvasRenderSceneSnapshot(
            identity: fixture.scene.identity,
            surfaceID: fixture.scene.surfaceID,
            objects: [clipped]
        )
        let plan = try CanvasRendererCore().prepare(
            scene: scene,
            overlays: .init(identity: scene.identity, overlays: []),
            viewport: fixture.viewport
        )

        let frame = try XCTUnwrap(plan.accessibilityElements.first?.frame)
        XCTAssertEqual(frame.origin, ViewportPoint(x: 0, y: 5))
        XCTAssertEqual(frame.size, ViewportSize(width: 30, height: 25))

        let viewportClipped = CanvasRenderObject(
            id: clipped.id,
            frame: WorldRect(
                origin: WorldPoint(x: 980, y: 690),
                size: WorldSize(width: 80, height: 40)
            ),
            clipRect: nil,
            paintOrder: 0,
            style: .frameSurface,
            isVisible: true,
            accessibilityLabel: "Viewport clipped frame"
        )
        let viewportScene = CanvasRenderSceneSnapshot(
            identity: scene.identity,
            surfaceID: scene.surfaceID,
            objects: [viewportClipped]
        )
        let viewportPlan = try CanvasRendererCore().prepare(
            scene: viewportScene,
            overlays: .init(identity: viewportScene.identity, overlays: []),
            viewport: fixture.viewport
        )
        let viewportFrame = try XCTUnwrap(viewportPlan.accessibilityElements.first?.frame)
        XCTAssertEqual(viewportFrame.origin, ViewportPoint(x: 980, y: 690))
        XCTAssertEqual(viewportFrame.size, ViewportSize(width: 20, height: 10))
    }

    // SF-0407-001, SF-0407-005
    func testEditorOverlaysAreStructurallyExcludedFromPreviewSnapshot() throws {
        let fixture = try makeFixture(count: 2)
        let overlay = CanvasEditorOverlay(
            id: CanvasOverlayID(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!),
            objectID: fixture.scene.objects[0].id,
            frame: fixture.scene.objects[0].frame,
            kind: "selection"
        )
        let overlays = CanvasEditorOverlaySnapshot(identity: fixture.scene.identity, overlays: [overlay])
        _ = try CanvasRendererCore().prepare(scene: fixture.scene, overlays: overlays, viewport: fixture.viewport)
        let preview = CanvasRendererCore().previewSnapshot(from: fixture.scene)
        XCTAssertEqual(preview.objects, fixture.scene.objects)
        XCTAssertFalse(String(describing: preview).contains("selection"))
        XCTAssertEqual(preview.deterministicDigest, CanvasRendererCore().previewSnapshot(from: fixture.scene).deterministicDigest)
    }

    // SF-0508-001, SF-0508-003, SF-0508-004, SF-0508-005
    func testAuthoredFillLayerCompositorPreservesOrderDisabledLayersStopsAnglesAndOpacity() throws {
        let bottom = fillLayer("11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa", rgba: [1, 0, 0, 1])
        let top = fillLayer("22222222-aaaa-aaaa-aaaa-aaaaaaaaaaaa", rgba: [0, 0, 1, 0.5])
        let disabled = CanvasAuthoredFillLayer(
            id: UUID(uuidString: "33333333-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            kind: .solid,
            isEnabled: false,
            rgba: [0, 1, 0, 1],
            angleDegrees: nil,
            stops: []
        )
        assertRGBA(
            try XCTUnwrap(CanvasAuthoredFillCompositor.resolvedColor(layers: [bottom, disabled, top], atNormalizedPoint: (x: 0.5, y: 0.5))),
            equals: [0.5, 0, 0.5, 1]
        )
        assertRGBA(
            try XCTUnwrap(CanvasAuthoredFillCompositor.resolvedColor(layers: [top, bottom], atNormalizedPoint: (x: 0.5, y: 0.5))),
            equals: [1, 0, 0, 1]
        )
        XCTAssertEqual(
            CanvasAuthoredFillCompositor.applyingObjectOpacity([0.5, 0, 0.5, 1], opacity: 0.4),
            [0.5, 0, 0.5, 0.4]
        )
        XCTAssertNil(CanvasAuthoredFillCompositor.applyingObjectOpacity([0, 0, 0], opacity: 1))

        let gradient = gradientLayer(
            "44444444-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            angle: 0,
            // Authored stop identity/order is deliberately not positional.
            stops: [
                gradientStop("aaaaaaaa-bbbb-cccc-dddd-000000000003", position: 1, rgba: [0, 0, 1, 1]),
                gradientStop("aaaaaaaa-bbbb-cccc-dddd-000000000001", position: 0, rgba: [1, 0, 0, 1]),
                gradientStop("aaaaaaaa-bbbb-cccc-dddd-000000000002", position: 0.5, rgba: [0, 1, 0, 1]),
            ]
        )
        XCTAssertEqual(CanvasAuthoredFillCompositor.interpolationStops(for: gradient).map(\.id), [
            UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-000000000001")!,
            UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-000000000002")!,
            UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-000000000003")!,
        ])
        assertRGBA(try XCTUnwrap(CanvasAuthoredFillCompositor.color(for: gradient, atNormalizedPoint: (x: 0.25, y: 0.5))), equals: [0.5, 0.5, 0, 1])
        assertRGBA(try XCTUnwrap(CanvasAuthoredFillCompositor.color(for: gradient, atNormalizedPoint: (x: 0.75, y: 0.5))), equals: [0, 0.5, 0.5, 1])
        let vertical = gradientLayer(
            "55555555-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            angle: 90,
            stops: [
                gradientStop("aaaaaaaa-bbbb-cccc-dddd-000000000004", position: 0, rgba: [0, 0, 0, 1]),
                gradientStop("aaaaaaaa-bbbb-cccc-dddd-000000000005", position: 1, rgba: [1, 1, 1, 1]),
            ]
        )
        assertRGBA(try XCTUnwrap(CanvasAuthoredFillCompositor.color(for: vertical, atNormalizedPoint: (x: 0.5, y: 0))), equals: [0, 0, 0, 1])
        assertRGBA(try XCTUnwrap(CanvasAuthoredFillCompositor.color(for: vertical, atNormalizedPoint: (x: 0.5, y: 1))), equals: [1, 1, 1, 1])
    }

    // SF-0508-001/003/004, SF-1204-003: native sampling, Add Stop and the Flow
    // runtime share CSS premultiplied sRGB interpolation. A transparent stop
    // contributes no color, opaque ramps stay linear, equal positions remain
    // hard edges in authored order, and invalid input is rejected, not clamped.
    func testPremultipliedGradientInterpolationMatchesCSSReferenceForAlphaHardStopsAndBounds() throws {
        func rgba(_ color: CanonicalSolidColor) -> [Double] { [color.red, color.green, color.blue, color.alpha] }
        func interpolate(_ a: [Double], _ b: [Double], _ t: Double) -> [Double]? {
            CanonicalSolidColor.premultipliedInterpolation(.init(red: a[0], green: a[1], blue: a[2], alpha: a[3]),
                .init(red: b[0], green: b[1], blue: b[2], alpha: b[3]), fraction: t).map(rgba)
        }
        // CSS Images 4: interpolate premultiplied components, then un-premultiply.
        func reference(_ a: [Double], _ b: [Double], _ t: Double) -> [Double] {
            let premultipliedA = a.prefix(3).map { $0 * a[3] }, premultipliedB = b.prefix(3).map { $0 * b[3] }
            let alpha = a[3] + (b[3] - a[3]) * t
            guard alpha > 0 else { return [0, 0, 0, 0] }
            return zip(premultipliedA, premultipliedB).map { ($0 + ($1 - $0) * t) / alpha } + [alpha]
        }
        let transparentRed = [1.0, 0, 0, 0], opaqueBlue = [0.0, 0, 1, 1]
        assertRGBA(try XCTUnwrap(interpolate(transparentRed, opaqueBlue, 0.5)), equals: [0, 0, 1, 0.5])
        assertRGBA(try XCTUnwrap(interpolate([1, 0, 0, 0.2], opaqueBlue, 0.5)), equals: [1.0 / 6.0, 0, 5.0 / 6.0, 0.6])
        assertRGBA(try XCTUnwrap(interpolate([1, 0, 0, 1], opaqueBlue, 0.25)), equals: [0.75, 0, 0.25, 1])
        assertRGBA(try XCTUnwrap(interpolate(transparentRed, [0, 1, 0, 0], 0.4)), equals: [0, 0, 0, 0])
        assertRGBA(try XCTUnwrap(interpolate([1, 0, 0, 0.2], opaqueBlue, 0)), equals: [1, 0, 0, 0.2])
        assertRGBA(try XCTUnwrap(interpolate([1, 0, 0, 0.2], opaqueBlue, 1)), equals: opaqueBlue)
        let samples: [[Double]] = [[1, 0, 0, 0], [0.2, 0.4, 0.6, 0.3], [0, 0, 1, 1], [0.9, 0.9, 0.1, 0.75]]
        for a in samples {
            for b in samples {
                for step in 0...10 {
                    let t = Double(step) / 10
                    let actual = try XCTUnwrap(interpolate(a, b, t))
                    assertRGBA(actual, equals: reference(a, b, t))
                    assertRGBA(actual, equals: try XCTUnwrap(interpolate(b, a, 1 - t)))
                }
            }
        }
        for fraction in [-0.01, 1.01, Double.nan, Double.infinity] {
            XCTAssertNil(interpolate([1, 0, 0, 1], opaqueBlue, fraction))
        }
        XCTAssertNil(interpolate([1.2, 0, 0, 1], opaqueBlue, 0.5))
        XCTAssertNil(interpolate([1, 0, 0, 1], [0, 0, 1, -0.5], 0.5))

        // Sampling sorts by position and keeps authored order for equal
        // positions, so a coincident pair stays a hard edge.
        func stop(_ identifier: String, _ position: Double, _ color: [Double]) -> CanvasGradientStop {
            CanvasGradientStop(id: UUID(uuidString: identifier)!, position: position, rgba: color)
        }
        let red = [1.0, 0, 0, 1]
        let layer = gradientLayer("44444444-aaaa-aaaa-aaaa-aaaaaaaaaaaa", angle: 0, stops: [
            stop("55555555-aaaa-aaaa-aaaa-aaaaaaaaaaaa", 1, opaqueBlue),
            stop("66666666-aaaa-aaaa-aaaa-aaaaaaaaaaaa", 0, red),
            stop("77777777-aaaa-aaaa-aaaa-aaaaaaaaaaaa", 0.5, red),
            stop("88888888-aaaa-aaaa-aaaa-aaaaaaaaaaaa", 0.5, opaqueBlue),
        ])
        let ordered = CanvasAuthoredFillCompositor.interpolationStops(for: layer)
        XCTAssertEqual(ordered.map(\.position), [0, 0.5, 0.5, 1])
        XCTAssertEqual(ordered.map(\.rgba), [red, red, opaqueBlue, opaqueBlue])
        for (position, expected) in [(-0.5, red), (0.0, red), (0.25, red), (0.4999, red), (0.5, opaqueBlue),
                                     (0.75, opaqueBlue), (1.0, opaqueBlue), (1.5, opaqueBlue)] {
            assertRGBA(try XCTUnwrap(CanvasAuthoredFillCompositor.gradientRGBA(orderedStops: ordered, at: position)), equals: expected)
        }
        XCTAssertNil(CanvasAuthoredFillCompositor.gradientRGBA(orderedStops: ordered, at: .nan))
        XCTAssertNil(CanvasAuthoredFillCompositor.gradientRGBA(orderedStops: [], at: 0.5))
        let alphaRamp = [stop("99999999-aaaa-aaaa-aaaa-aaaaaaaaaaaa", 0, transparentRed),
                         stop("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", 1, opaqueBlue)]
        for step in 1...9 {
            let t = Double(step) / 10
            let sample = try XCTUnwrap(CanvasAuthoredFillCompositor.gradientRGBA(orderedStops: alphaRamp, at: t))
            assertRGBA(sample, equals: [0, 0, 1, t])
        }
    }

    // SF-0508-001, SF-0508-004, SF-0508-005
    func testFillLayersAreImmutablePlanDataAndExcludeEditorOverlays() throws {
        let fixture = try makeFixture(count: 1)
        let legacyColor = [0.12, 0.34, 0.56, 0.78]
        let v1Layer = fillLayer("66666666-aaaa-aaaa-aaaa-aaaaaaaaaaaa", rgba: legacyColor)
        let object = CanvasRenderObject(
            id: fixture.scene.objects[0].id,
            frame: fixture.scene.objects[0].frame,
            clipRect: fixture.scene.objects[0].clipRect,
            paintOrder: 0,
            style: .frameSurface,
            isVisible: true,
            accessibilityLabel: "Frame",
            fillRGBA: legacyColor,
            fillLayers: [v1Layer],
            opacity: 0.5
        )
        let scene = CanvasRenderSceneSnapshot(identity: fixture.scene.identity, surfaceID: fixture.scene.surfaceID, objects: [object])
        let overlay = CanvasEditorOverlay(
            id: CanvasOverlayID(UUID(uuidString: "77777777-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!),
            objectID: object.id,
            frame: object.frame,
            kind: "selection"
        )
        let plan = try CanvasRendererCore().prepare(
            scene: scene,
            overlays: .init(identity: scene.identity, overlays: [overlay]),
            viewport: fixture.viewport
        )
        XCTAssertEqual(plan.authoredObjects.first?.fillLayers, [v1Layer])
        XCTAssertEqual(CanvasRendererCore().hitTest(WorldPoint(x: 5, y: 5), in: plan), object.id)
        let preview = CanvasRendererCore().previewSnapshot(from: scene)
        XCTAssertEqual(preview.objects.first?.fillLayers, [v1Layer])
        XCTAssertFalse(String(describing: preview).contains("selection"))

        var display = CanvasRenderDisplayState()
        try display.adopt(plan, expected: scene.identity)
        let staleIdentity = CanvasRenderRequestIdentity(
            documentID: scene.identity.documentID,
            revision: scene.identity.revision + 1,
            sceneID: scene.identity.sceneID,
            sceneGeneration: scene.identity.sceneGeneration,
            viewportGeneration: scene.identity.viewportGeneration,
            scale: scene.identity.scale
        )
        XCTAssertThrowsError(try display.adopt(plan, expected: staleIdentity))
        XCTAssertEqual(display.lastValidPlan?.authoredObjects.first?.fillLayers, [v1Layer])
    }

    // SF-0407-002, SF-0407-003, SF-0407-007
    func testIncrementalDirtyRegionsAndCompositorOnlyViewportChanges() throws {
        let fixture = try makeFixture(count: 4)
        var moved = fixture.scene.objects
        let original = moved[2]
        moved[2] = CanvasRenderObject(
            id: original.id,
            frame: WorldRect(origin: WorldPoint(x: 700, y: 300), size: original.frame.size),
            clipRect: original.clipRect,
            paintOrder: original.paintOrder,
            style: original.style,
            isVisible: true,
            accessibilityLabel: original.accessibilityLabel
        )
        let nextIdentity = CanvasRenderRequestIdentity(
            documentID: fixture.scene.identity.documentID,
            revision: fixture.scene.identity.revision,
            sceneID: fixture.scene.identity.sceneID,
            sceneGeneration: fixture.scene.identity.sceneGeneration,
            viewportGeneration: fixture.scene.identity.viewportGeneration + 1,
            scale: fixture.scene.identity.scale
        )
        let movedScene = CanvasRenderSceneSnapshot(identity: nextIdentity, surfaceID: fixture.scene.surfaceID, objects: moved)
        let movedOverlay = CanvasEditorOverlaySnapshot(identity: nextIdentity, overlays: [])
        let dirty = try CanvasRendererCore().prepare(
            scene: movedScene, overlays: movedOverlay, viewport: fixture.viewport, previous: fixture.scene
        )
        XCTAssertEqual(dirty.invalidation, .dirtyRegions)
        XCTAssertEqual(dirty.dirtyWorldRegions, [original.frame, moved[2].frame])

        let panOnlyScene = CanvasRenderSceneSnapshot(identity: nextIdentity, surfaceID: fixture.scene.surfaceID, objects: fixture.scene.objects)
        let compositor = try CanvasRendererCore().prepare(
            scene: panOnlyScene, overlays: movedOverlay, viewport: fixture.viewport, previous: fixture.scene
        )
        XCTAssertEqual(compositor.invalidation, .compositorOnly)
        XCTAssertTrue(compositor.dirtyWorldRegions.isEmpty)
    }

    // SF-0506-003/007/008 — shadow pixels may cross a tile boundary, but the
    // object's semantic geometry remains its authored frame.
    func testAuthoredShadowExpandsRasterTilesAndDirtyRegionsWithoutExpandingInteractionGeometry() throws {
        let fixture = try makeFixture(count: 1)
        let base = fixture.scene.objects[0]
        let styled = CanvasRenderObject(
            id: base.id,
            frame: .init(origin: .init(x: 240, y: 40), size: .init(width: 10, height: 10)),
            clipRect: base.clipRect,
            paintOrder: base.paintOrder,
            style: base.style,
            isVisible: true,
            accessibilityLabel: base.accessibilityLabel,
            shadow: .init(rgba: [0, 0, 0, 0.4], offsetX: 30, offsetY: 0, blur: 8, spread: 0)
        )
        let scene = CanvasRenderSceneSnapshot(
            identity: fixture.scene.identity,
            surfaceID: fixture.scene.surfaceID,
            objects: [styled]
        )
        let plan = try CanvasRendererCore().prepare(
            scene: scene,
            overlays: .init(identity: scene.identity, overlays: []),
            viewport: fixture.viewport
        )
        XCTAssertTrue(plan.tiles.first(where: { $0.id.column == 1 && $0.id.row == 0 })?.objectIDs.contains(styled.id) == true)
        XCTAssertEqual(plan.accessibilityElements.first?.objectID, styled.id)
        XCTAssertEqual(plan.accessibilityElements.first?.frame.size, .init(width: 10, height: 10))
        XCTAssertEqual(CanvasRendererCore().hitTest(.init(x: 245, y: 45), in: plan), styled.id)
        XCTAssertNil(CanvasRendererCore().hitTest(.init(x: 275, y: 45), in: plan))
        XCTAssertEqual(plan.dirtyWorldRegions.first?.minX, 232)
        XCTAssertEqual(plan.dirtyWorldRegions.first?.maxX, 288)
    }

    // SF-0407-004, SF-0407-008
    func testInvalidNonfiniteDuplicateOversizedAndIncompatibleInputsAreRejected() throws {
        let fixture = try makeFixture(count: 2)
        XCTAssertThrowsError(try CanvasRendererCore().prepare(
            scene: CanvasRenderSceneSnapshot(schemaVersion: 999, identity: fixture.scene.identity, surfaceID: fixture.scene.surfaceID, objects: fixture.scene.objects),
            overlays: fixture.overlays,
            viewport: fixture.viewport
        ))
        XCTAssertThrowsError(try CanvasRendererCore().prepare(
            scene: CanvasRenderSceneSnapshot(identity: fixture.scene.identity, surfaceID: fixture.scene.surfaceID, objects: [fixture.scene.objects[0], fixture.scene.objects[0]]),
            overlays: fixture.overlays,
            viewport: fixture.viewport
        ))
        var incompatible = fixture.scene.identity
        incompatible = CanvasRenderRequestIdentity(
            documentID: incompatible.documentID, revision: incompatible.revision + 1,
            sceneID: incompatible.sceneID, sceneGeneration: incompatible.sceneGeneration,
            viewportGeneration: incompatible.viewportGeneration, scale: incompatible.scale
        )
        XCTAssertThrowsError(try CanvasRendererCore().prepare(
            scene: fixture.scene,
            overlays: CanvasEditorOverlaySnapshot(identity: incompatible, overlays: []),
            viewport: fixture.viewport
        ))
    }

    // SF-0407-004, SF-0407-007
    func testCancellationAndEveryStaleIdentityDimensionPreserveLastValidDisplay() throws {
        let fixture = try makeFixture(count: 100)
        let valid = try CanvasRendererCore().prepare(scene: fixture.scene, overlays: fixture.overlays, viewport: fixture.viewport)
        var display = CanvasRenderDisplayState()
        try display.adopt(valid, expected: fixture.scene.identity)
        XCTAssertThrowsError(try CanvasRendererCore().prepare(
            scene: fixture.scene, overlays: fixture.overlays, viewport: fixture.viewport,
            cancellation: CanvasRenderCancellation { $0 >= 64 }
        ))
        let dimensions: [CanvasRenderRequestIdentity] = [
            CanvasRenderRequestIdentity(documentID: DocumentID(), revision: valid.identity.revision, sceneID: valid.identity.sceneID, sceneGeneration: valid.identity.sceneGeneration, viewportGeneration: valid.identity.viewportGeneration, scale: valid.identity.scale),
            CanvasRenderRequestIdentity(documentID: valid.identity.documentID, revision: valid.identity.revision + 1, sceneID: valid.identity.sceneID, sceneGeneration: valid.identity.sceneGeneration, viewportGeneration: valid.identity.viewportGeneration, scale: valid.identity.scale),
            CanvasRenderRequestIdentity(documentID: valid.identity.documentID, revision: valid.identity.revision, sceneID: CanvasViewportSceneID(), sceneGeneration: valid.identity.sceneGeneration, viewportGeneration: valid.identity.viewportGeneration, scale: valid.identity.scale),
            CanvasRenderRequestIdentity(documentID: valid.identity.documentID, revision: valid.identity.revision, sceneID: valid.identity.sceneID, sceneGeneration: valid.identity.sceneGeneration + 1, viewportGeneration: valid.identity.viewportGeneration, scale: valid.identity.scale),
            CanvasRenderRequestIdentity(documentID: valid.identity.documentID, revision: valid.identity.revision, sceneID: valid.identity.sceneID, sceneGeneration: valid.identity.sceneGeneration, viewportGeneration: valid.identity.viewportGeneration + 1, scale: valid.identity.scale),
            CanvasRenderRequestIdentity(documentID: valid.identity.documentID, revision: valid.identity.revision, sceneID: valid.identity.sceneID, sceneGeneration: valid.identity.sceneGeneration, viewportGeneration: valid.identity.viewportGeneration, scale: try CanvasPixelRatio(1)),
        ]
        for stale in dimensions {
            XCTAssertThrowsError(try display.adopt(valid, expected: stale))
            XCTAssertEqual(display.lastValidPlan, valid)
        }
    }

    // SF-0407-006, SF-0407-007
    func testAccessibilityVirtualizationIsStableBoundedAndViewportScoped() throws {
        let fixture = try makeFixture(count: 10_000)
        let first = try CanvasRendererCore().prepare(scene: fixture.scene, overlays: fixture.overlays, viewport: fixture.viewport)
        let second = try CanvasRendererCore().prepare(scene: fixture.scene, overlays: fixture.overlays, viewport: fixture.viewport)
        XCTAssertLessThanOrEqual(first.accessibilityElements.count, CanvasRendererPolicy.maximumAccessibilityElements)
        XCTAssertEqual(first.accessibilityElements, second.accessibilityElements)
        XCTAssertEqual(Set(first.accessibilityElements.map(\.id)).count, first.accessibilityElements.count)
    }

    // SF-0407-006
    func testAccessibilityFocusIsPreservedOrDeterministicallyRepaired() throws {
        let fixture = try makeFixture(count: 3)
        let plan = try CanvasRendererCore().prepare(
            scene: fixture.scene,
            overlays: fixture.overlays,
            viewport: fixture.viewport
        )
        let retained = plan.accessibilityElements[1].objectID
        XCTAssertEqual(
            CanvasAccessibilityFocusPolicy.repairedFocus(
                previousObjectID: retained,
                elements: plan.accessibilityElements
            ),
            retained
        )
        XCTAssertEqual(
            CanvasAccessibilityFocusPolicy.repairedFocus(
                previousObjectID: NodeID(),
                elements: plan.accessibilityElements
            ),
            plan.accessibilityElements.first?.objectID
        )
        XCTAssertNil(CanvasAccessibilityFocusPolicy.repairedFocus(
            previousObjectID: retained,
            elements: []
        ))
    }

    // SF-0201-006, SF-0407-006, SF-1505-006 — a delayed native canvas focus
    // request cannot override a newer rapid traversal destination.
    func testCanvasFocusAdoptionRejectsStaleDelayedRequests() {
        var gate = CanvasFocusAdoptionGate()
        let first = gate.issue(whenRequested: true)
        XCTAssertNotNil(first)
        XCTAssertTrue(gate.accepts(first!))

        XCTAssertNil(gate.issue(whenRequested: false))
        XCTAssertFalse(gate.accepts(first!))

        let newest = gate.issue(whenRequested: true)
        XCTAssertNotNil(newest)
        XCTAssertFalse(gate.accepts(first!))
        XCTAssertTrue(gate.accepts(newest!))

        gate.cancel()
        XCTAssertFalse(gate.accepts(newest!))
    }

    // SF-0201-006, SF-0407-006 — AX reports success only when the production
    // command callback exists and confirms an actual accepted mutation.
    func testCanvasAccessibilityActionDispatcherReturnsTruthfulMutationResult() {
        XCTAssertFalse(CanvasAccessibilityActionDispatcher.perform(nil))
        XCTAssertFalse(CanvasAccessibilityActionDispatcher.perform { false })
        XCTAssertTrue(CanvasAccessibilityActionDispatcher.perform { true })

        var mutationCount = 0
        XCTAssertTrue(CanvasAccessibilityActionDispatcher.perform {
            mutationCount += 1
            return true
        })
        XCTAssertEqual(mutationCount, 1)
    }

    // SF-0407-007, SF-0407-008
    func testTilesAndCacheAreBoundedWithDeterministicEviction() throws {
        let fixture = try makeFixture(count: 100)
        var cache = CanvasRenderCache()
        for generation in 0...3 {
            let identity = CanvasRenderRequestIdentity(
                documentID: fixture.scene.identity.documentID, revision: fixture.scene.identity.revision,
                sceneID: fixture.scene.identity.sceneID, sceneGeneration: fixture.scene.identity.sceneGeneration,
                viewportGeneration: UInt64(generation), scale: fixture.scene.identity.scale
            )
            let scene = CanvasRenderSceneSnapshot(identity: identity, surfaceID: fixture.scene.surfaceID, objects: fixture.scene.objects)
            let plan = try CanvasRendererCore().prepare(
                scene: scene, overlays: CanvasEditorOverlaySnapshot(identity: identity, overlays: []), viewport: fixture.viewport
            )
            XCTAssertLessThanOrEqual(plan.tiles.count, CanvasRendererPolicy.maximumTiles)
            XCTAssertLessThanOrEqual(plan.tiles.reduce(0) { $0 + $1.estimatedBytes }, CanvasRendererPolicy.maximumCacheBytes)
            cache.insert(plan)
        }
        XCTAssertEqual(cache.order.count, CanvasRendererPolicy.maximumRetainedGenerations)
        XCTAssertEqual(cache.order.map(\.viewportGeneration), [2, 3])
    }

    // SF-0407-008
    func testDiagnosticsAreBoundedAndRedacted() throws {
        let fixture = try makeFixture(count: 2)
        let plan = try CanvasRendererCore().prepare(scene: fixture.scene, overlays: fixture.overlays, viewport: fixture.viewport)
        let record = CanvasRenderDiagnosticFactory.make(
            operation: "prepare", plan: plan, identity: fixture.scene.identity,
            surfaceID: fixture.scene.surfaceID, durationMilliseconds: 1.25,
            result: .failure,
            failureCategory: "invalid-input-" + String(repeating: "x", count: 200)
        )
        let encoded = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
        XCTAssertEqual(record.requirementID, "SF-0407-008")
        XCTAssertEqual(record.surfaceIdentifier.count, "surface-".count + 24)
        XCTAssertFalse(record.surfaceIdentifier.contains(fixture.scene.surfaceID.description))
        XCTAssertEqual(record.failureCategory, DiagnosticErrorCategory.invalidInput.rawValue)
        XCTAssertLessThanOrEqual(record.failureCategory?.count ?? 0, 64)
        XCTAssertFalse(encoded.contains("/Users/"))
        XCTAssertFalse(encoded.contains(fixture.scene.objects[0].accessibilityLabel))
    }

    // SF-0402-001, SF-0402-003, SF-0402-006, SF-0402-008, SF-0407-006 —
    // an implicit geometry-less page root is Layers ownership, not a visible
    // canvas object. Its direct authored children remain page-level selection
    // candidates after opening an existing project.
    func testProductionProjectionKeepsStructuralRootOutOfCanvasTraversal() async throws {
        let documentID = DocumentID(UUID(uuidString: "66666666-1111-4111-8111-111111111111")!)
        var document = ProjectCreation.blank(id: documentID)
        var page = try XCTUnwrap(document.pages.first)
        let rootID = try XCTUnwrap(page.rootNodeIDs.first)
        let rootIndex = try XCTUnwrap(page.nodes.firstIndex(where: { $0.id == rootID }))
        let textID = NodeID(UUID(uuidString: "66666666-2222-4222-8222-222222222222")!)
        page.nodes[rootIndex].childIDs.append(textID)
        page.nodes.append(DocumentNode(
            id: textID,
            kind: .text,
            name: "Text",
            parent: .node(rootID),
            properties: [
                .init(key: .init(rawValue: "layout.x"), value: .number(100), origin: .defaulted),
                .init(key: .init(rawValue: "layout.y"), value: .number(120), origin: .defaulted),
                .init(key: .init(rawValue: "layout.width"), value: .number(120), origin: .defaulted),
                .init(key: .init(rawValue: "layout.height"), value: .number(24), origin: .defaulted),
                .init(key: .init(rawValue: "content.text"), value: .string("Text"), origin: .defaulted),
            ]
        ))
        document.pages[0] = page
        let viewport = try CanvasViewportState(
            worldOrigin: .init(x: 0, y: 0),
            viewportSize: .init(width: 1_000, height: 700),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1_440, height: 900)),
            pixelRatio: .init(2)
        )
        let prepared = try await WorkspaceScenePreparationWorker().prepare(
            WorkspaceScenePreparationRequest(
                document: document,
                activePageID: page.id,
                activeContainerID: nil,
                viewport: viewport,
                surfaceID: CanvasRenderSurfaceID(UUID(uuidString: "66666666-3333-4333-8333-333333333333")!)
            )
        )
        let selectionScene = try XCTUnwrap(prepared.selectionScene)
        let root = try XCTUnwrap(selectionScene.targets.first(where: { $0.id == rootID }))
        let text = try XCTUnwrap(selectionScene.targets.first(where: { $0.id == textID }))
        XCTAssertFalse(root.participatesInCanvasTraversal)
        XCTAssertTrue(text.participatesInCanvasTraversal)
        XCTAssertNil(text.parentID, "The implicit structural root is transparent to page-level selection scope")
        XCTAssertEqual(selectionScene.orderedSelectableTargets.map(\.id), [textID])
        XCTAssertEqual(prepared.renderScene.objects.map(\.id), [textID])

        let plan = try CanvasRendererCore().prepare(
            scene: prepared.renderScene,
            overlays: prepared.overlays,
            viewport: viewport
        )
        let registry = SelectionCommandRegistry()
        var state = SelectionState()
        _ = try registry.adopt(selectionScene, boundary: .documentAdoption, state: &state)
        _ = try registry.apply(
            .init(.replace, targetID: rootID, expectedIdentity: selectionScene.identity, provenance: .layersNavigator),
            to: &state,
            scene: selectionScene
        )
        let rootOverlay = try SelectionOverlayPlanner().plan(
            selection: state,
            scene: selectionScene,
            renderPlan: plan
        )
        XCTAssertTrue(rootOverlay.overlays.isEmpty)

        XCTAssertEqual(
            try registry.apply(
                .init(.next, expectedIdentity: selectionScene.identity, provenance: .accessibility),
                to: &state,
                scene: selectionScene
            ),
            .changed
        )
        XCTAssertEqual(state.primaryID, textID)
        XCTAssertEqual(
            try registry.apply(
                .init(.next, expectedIdentity: selectionScene.identity, provenance: .accessibility),
                to: &state,
                scene: selectionScene
            ),
            .unchanged
        )
        XCTAssertEqual(state.primaryID, textID)
    }

    // SF-0504-003/SF-0510-003/SF-0511-003 — one immutable preparation
    // snapshot owns z-order, positioned geometry, reusable appearance, state
    // preview, selection geometry, hit testing, and accessibility geometry.
    func testAdvancedStyleProjectionAdoptsPositionZOrderAndForcedStateAtomically() async throws {
        var document = ProjectCreation.blank()
        var page = try XCTUnwrap(document.pages.first)
        let rootID = try XCTUnwrap(page.rootNodeIDs.first)
        let rootIndex = try XCTUnwrap(page.nodes.firstIndex { $0.id == rootID })
        let backID = NodeID(UUID(uuidString: "97100000-0000-4000-8000-000000000001")!)
        let frontID = NodeID(UUID(uuidString: "97100000-0000-4000-8000-000000000002")!)
        let styleID = ReusableStyleID(UUID(uuidString: "97100000-0000-4000-8000-000000000003")!)
        let hoverID = UUID(uuidString: "97100000-0000-4000-8000-000000000004")!
        func geometry(_ x: Double, _ y: Double) -> [NodeProperty] {
            let values: [(String, Double)] = [
                ("layout.x", x), ("layout.y", y), ("layout.width", 120), ("layout.height", 80),
            ]
            return values.map {
                .init(key: .init(rawValue: $0.0), value: .number($0.1), origin: .authored)
            }
        }
        let prefix = CanonicalReusableStyleIndex.namespace + "definition.\(styleID.description)."
        page.nodes[rootIndex].properties += [
            .init(key: .init(rawValue: prefix + "name"), value: .string("Card"), origin: .authored),
            .init(key: .init(rawValue: prefix + "fill"), value: .string("#CC1933FF"), origin: .authored),
            .init(key: .init(rawValue: prefix + "opacity"), value: .number(0.75), origin: .authored),
        ]
        page.nodes[rootIndex].childIDs += [frontID, backID]
        page.nodes.append(.init(id: frontID, kind: .frame, name: "Front", parent: .node(rootID), properties:
            geometry(20, 30) + [
                .init(key: .init(rawValue: CanonicalReusableStyleIndex.appliedKey), value: .string(styleID.description), origin: .authored),
                .init(key: .init(rawValue: CanonicalPositioning.namespace + "mode"), value: .string("relative"), origin: .authored),
                .init(key: .init(rawValue: CanonicalPositioning.namespace + "left"), value: .number(10), origin: .authored),
                .init(key: .init(rawValue: CanonicalPositioning.namespace + "top"), value: .number(12), origin: .authored),
                .init(key: .init(rawValue: CanonicalPositioning.namespace + "zIndex"), value: .number(5), origin: .authored),
                .init(key: .init(rawValue: CanonicalReusableStyleIndex.stateNamespace + "hover.id"), value: .string(hoverID.uuidString.lowercased()), origin: .authored),
                .init(key: .init(rawValue: CanonicalReusableStyleIndex.stateNamespace + "hover.fill"), value: .string("#1933CCFF"), origin: .authored),
            ]))
        page.nodes.append(.init(id: backID, kind: .frame, name: "Back", parent: .node(rootID), properties: geometry(20, 30)))
        document.pages[0] = page
        let viewport = try CanvasViewportState(viewportSize: .init(width: 800, height: 600),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1_440, height: 900)),
            pixelRatio: .init(2))
        let prepared = try await WorkspaceScenePreparationWorker().prepare(.init(
            document: document, activePageID: page.id, activeContainerID: nil,
            forcedStyleState: .hover, viewport: viewport, surfaceID: CanvasRenderSurfaceID()))
        XCTAssertEqual(prepared.renderScene.objects.map(\.id), [backID, frontID])
        let object = try XCTUnwrap(prepared.renderScene.objects.first { $0.id == frontID })
        XCTAssertEqual(object.frame.origin, .init(x: 30, y: 42))
        XCTAssertNil(object.fillRGBA, "Layered fill data is the single authored paint source.")
        XCTAssertEqual(object.fillLayers.count, 1)
        XCTAssertEqual(object.fillLayers.first?.kind, .solid)
        XCTAssertEqual(object.fillLayers.first?.rgba, [25.0 / 255, 51.0 / 255, 204.0 / 255, 1])
        XCTAssertEqual(object.opacity, 0.75)
        let target = try XCTUnwrap(prepared.selectionScene?.targets.first { $0.id == frontID })
        XCTAssertEqual(target.frame, object.frame)
        let plan = try CanvasRendererCore().prepare(scene: prepared.renderScene,
            overlays: prepared.overlays, viewport: viewport)
        XCTAssertEqual(plan.accessibilityElements.first { $0.objectID == frontID }?.frame.origin,
                       try viewport.transform.worldToViewport(object.frame.origin))
        XCTAssertEqual(CanvasRendererCore().hitTest(.init(x: 35, y: 47), in: plan), frontID)
    }

    // SF-0601-003, SF-0602-002/003/005/008
    func testResponsiveProjectionSharesResolvedGeometryWithRendererSelectionAndAccessibility() async throws {
        var document = ProjectCreation.blank()
        var page = try XCTUnwrap(document.pages.first)
        let rootID = try XCTUnwrap(page.rootNodeIDs.first)
        let rootIndex = try XCTUnwrap(page.nodes.firstIndex { $0.id == rootID })
        let nodeID = NodeID(UUID(uuidString: "60600000-0000-4000-8000-000000000001")!)
        var properties: [NodeProperty] = [
            .init(key: .init(rawValue: "layout.x"), value: .number(100), origin: .defaulted),
            .init(key: .init(rawValue: "layout.y"), value: .number(120), origin: .defaulted),
            .init(key: .init(rawValue: "layout.width"), value: .number(240), origin: .defaulted),
            .init(key: .init(rawValue: "layout.height"), value: .number(160), origin: .defaulted),
        ]
        for (field, value) in [(GeometryInspectorField.x, 24.0), (.y, 32), (.width, 342), (.height, 220)] {
            properties.append(.init(key: .init(rawValue: ResponsiveGeometryResolver.key(field, breakpoint: .mobile)),
                value: .number(value), origin: .authored))
        }
        page.nodes[rootIndex].childIDs.append(nodeID)
        page.nodes.append(.init(id: nodeID, kind: .frame, name: "Responsive Frame", parent: .node(rootID), properties: properties))
        document.pages[0] = page
        let viewport = try CanvasViewportState(viewportSize: .init(width: 800, height: 700),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 390, height: 900)), pixelRatio: .init(2))
        let prepared = try await WorkspaceScenePreparationWorker().prepare(.init(document: document,
            activePageID: page.id, activeContainerID: nil, viewport: viewport, surfaceID: CanvasRenderSurfaceID(),
            breakpoint: .mobile))
        let object = try XCTUnwrap(prepared.renderScene.objects.first { $0.id == nodeID })
        let target = try XCTUnwrap(prepared.selectionScene?.targets.first { $0.id == nodeID })
        XCTAssertEqual(object.frame, .init(origin: .init(x: 24, y: 32), size: .init(width: 342, height: 220)))
        XCTAssertEqual(target.frame, object.frame)
        let renderer = CanvasRendererCore()
        let plan = try renderer.prepare(scene: prepared.renderScene, overlays: prepared.overlays, viewport: viewport)
        XCTAssertEqual(plan.authoredObjects.first { $0.id == nodeID }?.frame, object.frame)
        let accessibility = try XCTUnwrap(plan.accessibilityElements.first { $0.objectID == nodeID })
        XCTAssertEqual(accessibility.frame.origin, try viewport.transform.worldToViewport(object.frame.origin))
        XCTAssertEqual(accessibility.frame.size.width, object.frame.size.width * viewport.zoom.value)
        XCTAssertEqual(renderer.hitTest(.init(x: 30, y: 40), in: plan), nodeID)
    }

    // SF-0510-003, SF-1204-003: linked border, corner
    // radius and shadow draw on the canvas and export to the static site
    // through one rule, so both agree object by object; an object's own value
    // and a disabled own shadow still win; unlinked objects are unchanged.
    func testLinkedBoxStylesDrawOnCanvasAndExportIdentically() async throws {
        var document = ProjectCreation.blank()
        let rootID = document.pages[0].rootNodeIDs[0]
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == rootID })
        let styleID = ReusableStyleID()
        let border = CanonicalBorder(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#336699FF")),
                                     width: 2, style: .solid)
        let shadow = CanonicalShadow(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#00000040")),
                                     offsetX: 0, offsetY: 4, blur: 10, spread: 0)
        let box = CanonicalReusableBoxAppearance(border: border, cornerRadius: 8, shadow: shadow)
        let prefix = CanonicalReusableStyleIndex.namespace + "definition.\(styleID.description)."
        document.pages[0].nodes[rootIndex].properties.append(.init(key: .init(rawValue: prefix + "name"),
            value: .string("Card"), origin: .authored))
        document.pages[0].nodes[rootIndex].properties += box.fieldValues.map {
            NodeProperty(key: .init(rawValue: prefix + $0.field), value: $0.value, origin: .authored)
        }
        func frame(_ name: String, x: Double, linked: Bool, extra: [NodeProperty] = []) -> DocumentNode {
            var properties: [NodeProperty] = [("layout.x", x), ("layout.y", 40.0), ("layout.width", 160.0), ("layout.height", 100.0)].map {
                .init(key: .init(rawValue: $0.0), value: .number($0.1), origin: .authored)
            }
            if linked {
                properties.append(.init(key: .init(rawValue: CanonicalReusableStyleIndex.appliedKey),
                                        value: .string(styleID.description), origin: .authored))
            }
            return DocumentNode(kind: .frame, name: name, parent: .node(rootID), properties: properties + extra)
        }
        let ns = DesignBoxStyleCommandRegistry.namespace
        let linkedCard = frame("Linked", x: 20, linked: true)
        let overridden = frame("Overridden", x: 200, linked: true, extra: [
            .init(key: .init(rawValue: ns + "radius.uniform"), value: .number(0), origin: .authored),
            .init(key: .init(rawValue: ns + "shadow.enabled"), value: .boolean(false), origin: .authored),
        ] + [("shadow.offsetX", 1.0), ("shadow.offsetY", 1.0), ("shadow.blur", 2.0), ("shadow.spread", 0.0),
             ("shadow.color.red", 0.0), ("shadow.color.green", 0.0), ("shadow.color.blue", 0.0), ("shadow.color.alpha", 1.0)].map {
            NodeProperty(key: .init(rawValue: ns + $0.0), value: .number($0.1), origin: .authored)
        })
        let plain = frame("Plain", x: 380, linked: false)
        document.pages[0].nodes[rootIndex].childIDs += [linkedCard.id, overridden.id, plain.id]
        document.pages[0].nodes += [linkedCard, overridden, plain]
        try document.validate()

        let viewport = try CanvasViewportState(viewportSize: .init(width: 1200, height: 800),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1440, height: 900)), pixelRatio: .init(2))
        let prepared = try await WorkspaceScenePreparationWorker().prepare(.init(document: document,
            activePageID: document.pages[0].id, activeContainerID: nil, viewport: viewport, surfaceID: CanvasRenderSurfaceID()))
        func object(_ id: NodeID) throws -> CanvasRenderObject {
            try XCTUnwrap(prepared.renderScene.objects.first { $0.id == id })
        }
        let rgba = [border.color.red, border.color.green, border.color.blue, border.color.alpha]
        XCTAssertEqual(try object(linkedCard.id).border, CanvasAuthoredBorder(rgba: rgba, width: 2, style: .solid))
        XCTAssertEqual(try object(linkedCard.id).cornerRadius, 8)
        XCTAssertEqual(try object(linkedCard.id).shadow, CanvasAuthoredShadow(
            rgba: [shadow.color.red, shadow.color.green, shadow.color.blue, shadow.color.alpha],
            offsetX: 0, offsetY: 4, blur: 10, spread: 0))
        XCTAssertEqual(try object(overridden.id).border?.width, 2, "Groups the object does not set stay linked")
        XCTAssertEqual(try object(overridden.id).cornerRadius, 0, "An own zero radius wins")
        XCTAssertNil(try object(overridden.id).shadow, "An own disabled shadow wins over the linked one")
        XCTAssertNil(try object(plain.id).border)
        XCTAssertEqual(try object(plain.id).cornerRadius, 0)
        XCTAssertNil(try object(plain.id).shadow)
        let renderer = CanvasRendererCore()
        XCTAssertNoThrow(try renderer.prepare(scene: prepared.renderScene, overlays: prepared.overlays, viewport: viewport))

        let plan = try MultiPageStaticBuildPlanner.plan(document: document)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        // Every rule for the object (layout, fills and box style are separate rules).
        func rule(_ id: NodeID) -> String {
            let selector = CanonicalCSSRule.selector(for: id) + " { "
            return css.split(separator: "\n").map(String.init).filter { $0.hasPrefix(selector) }.joined(separator: "\n")
        }
        // Connected pages emit the border as an outline; the values are the same.
        XCTAssertTrue(rule(linkedCard.id).contains("2.0px solid rgba(51.0, 102.0, 153.0, 1.0)"), css)
        XCTAssertTrue(rule(linkedCard.id).contains("border-radius: 8.0px;"), css)
        XCTAssertTrue(rule(linkedCard.id).contains("box-shadow: 0.0px 4.0px 10.0px 0.0px rgba(0.0, 0.0, 0.0, 0.251);"), css)
        XCTAssertTrue(rule(overridden.id).contains("2.0px solid rgba(51.0, 102.0, 153.0, 1.0)"), css)
        XCTAssertTrue(rule(overridden.id).contains("border-radius: 0.0px;"), css)
        XCTAssertFalse(rule(overridden.id).contains("box-shadow"), css)
        for absent in ["solid rgba", "border-radius", "box-shadow"] {
            XCTAssertFalse(rule(plain.id).contains(absent), "\(absent): \(css)")
        }
        XCTAssertFalse(css.contains("style.reusable"), "Style definitions never leak into output")

        // Updating the style updates every linked object in both places.
        var restyled = document
        let radiusKey = prefix + "cornerRadius"
        let radiusIndex = try XCTUnwrap(restyled.pages[0].nodes[rootIndex].properties.firstIndex { $0.key.rawValue == radiusKey })
        let old = restyled.pages[0].nodes[rootIndex].properties[radiusIndex]
        restyled.pages[0].nodes[rootIndex].properties[radiusIndex] = .init(id: old.id, key: old.key, value: .number(20), origin: .authored)
        try restyled.validate()
        let restyledScene = try await WorkspaceScenePreparationWorker().prepare(.init(document: restyled,
            activePageID: restyled.pages[0].id, activeContainerID: nil, viewport: viewport, surfaceID: CanvasRenderSurfaceID()))
        XCTAssertEqual(restyledScene.renderScene.objects.first { $0.id == linkedCard.id }?.cornerRadius, 20)
        XCTAssertEqual(restyledScene.renderScene.objects.first { $0.id == overridden.id }?.cornerRadius, 0)
        let restyledCSS = try XCTUnwrap(try MultiPageStaticBuildPlanner.plan(document: restyled)
            .files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(restyledCSS.contains("border-radius: 20.0px;"), restyledCSS)
    }

    // SF-0903-001/003/007, OD-018: one Card definition with slot "Content"
    // (Frame at 16, 60; default Text "Default"). On the page: Custom supplies a
    // Text and a Frame with a Text inside, Empty shows nothing, Inherit keeps
    // the default. Canvas, export and Preview agree; supplied objects keep
    // their canonical identities at slot origin + slot-local offset, follow
    // responsive overrides in slot-local terms, and resolve identically after
    // save/reopen. Contents for a slot the definition no longer exposes are
    // not drawn.
    func testSuppliedSlotContentDrawsInItsSlotWithCanonicalIdentityOnCanvasExportAndPreview() async throws {
        let fixture = try suppliedCardFixture()
        let document = fixture.document
        try document.validate()
        let resolved = try ComponentGraphResolver.resolvedPage(document.pages[0], in: document, breakpoint: .desktop)
        XCTAssertEqual(Set(resolved.nodes.map(\.id)).count, resolved.nodes.count)
        func slotContainer(_ instance: NodeID) throws -> NodeID {
            ComponentGraphResolver.derivedID(fixture.slotNodeID, in: try XCTUnwrap(document.pages[0].nodes.first { $0.id == instance }))
        }
        let byID = Dictionary(uniqueKeysWithValues: resolved.nodes.map { ($0.id, $0) })
        let customSlot = try XCTUnwrap(byID[try slotContainer(fixture.custom)])
        XCTAssertEqual(customSlot.childIDs, [fixture.suppliedText, fixture.suppliedFrame], "Supplied order, canonical identities")
        let text = try XCTUnwrap(byID[fixture.suppliedText])
        XCTAssertEqual(text.parent, .node(customSlot.id))
        XCTAssertEqual(text.insertionGeometry?.origin, WorldPoint(x: 40 + 16 + 8, y: 60 + 60 + 4),
                       "Instance origin + slot offset + slot-local offset")
        XCTAssertNil(text.insertionProperty(CanonicalComponentSlot.supplyKey), "Membership is storage, not output")
        let inner = try XCTUnwrap(byID[fixture.suppliedInnerText])
        XCTAssertEqual(inner.parent, .node(fixture.suppliedFrame))
        XCTAssertEqual(inner.insertionGeometry?.origin, WorldPoint(x: 40 + 16 + 100, y: 60 + 60 + 40))
        func defaultFor(_ instance: NodeID) throws -> NodeID {
            ComponentGraphResolver.derivedID(fixture.defaultTextID,
                in: try XCTUnwrap(document.pages[0].nodes.first { $0.id == instance }))
        }
        let customDefault = try defaultFor(fixture.custom), emptyDefault = try defaultFor(fixture.empty)
        let inheritDefault = try defaultFor(fixture.inherit)
        let emptySlot = try slotContainer(fixture.empty), inheritSlot = try slotContainer(fixture.inherit)
        XCTAssertNil(byID[customDefault], "Supplied contents replace the default")
        XCTAssertEqual(byID[emptySlot]?.childIDs, [])
        XCTAssertNil(byID[emptyDefault])
        XCTAssertEqual(byID[inheritSlot]?.childIDs, [inheritDefault])
        XCTAssertEqual(try ComponentGraphResolver.resolvedPage(document.pages[0], in: document, breakpoint: .desktop), resolved)
        let reopened = try DocumentSerializer.decode(DocumentSerializer.encode(document))
        XCTAssertEqual(try ComponentGraphResolver.resolvedPage(reopened.pages[0], in: reopened, breakpoint: .desktop), resolved)

        let mobile = try ComponentGraphResolver.resolvedPage(document.pages[0], in: document, breakpoint: .mobile)
        let mobileText = try XCTUnwrap(mobile.nodes.first { $0.id == fixture.suppliedText })
        XCTAssertEqual(mobileText.insertionGeometry?.origin.x, 40 + 16 + 2, "Mobile override is slot-local too")
        XCTAssertFalse(mobileText.properties.contains { $0.key.rawValue.hasPrefix(ResponsiveGeometryResolver.namespace + ".") },
                       "Already resolved; never re-applied in world terms")

        let viewport = try CanvasViewportState(viewportSize: .init(width: 1200, height: 800),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1440, height: 900)), pixelRatio: .init(2))
        let prepared = try await WorkspaceScenePreparationWorker().prepare(.init(document: document,
            activePageID: document.pages[0].id, activeContainerID: nil, viewport: viewport, surfaceID: CanvasRenderSurfaceID()))
        let drawn = try XCTUnwrap(prepared.renderScene.objects.first { $0.id == fixture.suppliedText })
        XCTAssertEqual(drawn.plainText, "Custom")
        XCTAssertEqual(drawn.frame.origin.x, 64, accuracy: 0.001)
        XCTAssertEqual(prepared.renderScene.objects.filter { $0.plainText == "Default" }.count, 1, "Only Inherit shows the default")

        let plan = try MultiPageStaticBuildPlanner.plan(document: document)
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        XCTAssertEqual(html.components(separatedBy: ">Custom<").count - 1, 1, html)
        XCTAssertEqual(html.components(separatedBy: ">Inside<").count - 1, 1, html)
        XCTAssertEqual(html.components(separatedBy: ">Default<").count - 1, 1, html)
        XCTAssertNotNil(StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .development),
            resourceDescriptors: [:], resourceData: [:]).plan)
        let preview = try await LocalPreviewRuntimeCompiler().compile(document: document, imageResourceData: [:],
                                                                      pixelRatio: CanvasPixelRatio(1))
        XCTAssertFalse(preview.pages.isEmpty)

        // The slot is no longer exposed: Custom's contents are kept but not drawn.
        var orphaned = document
        let definitionIndex = try XCTUnwrap(orphaned.pages.firstIndex { $0.role == .componentDefinition })
        let slotIndex = try XCTUnwrap(orphaned.pages[definitionIndex].nodes.firstIndex { $0.id == fixture.slotNodeID })
        orphaned.pages[definitionIndex].nodes[slotIndex].properties.removeAll {
            CanonicalComponentSlot.metadataKeys.contains($0.key.rawValue)
        }
        try orphaned.validate()
        let hidden = try ComponentGraphResolver.resolvedPage(orphaned.pages[0], in: orphaned, breakpoint: .desktop)
        XCTAssertFalse(hidden.nodes.contains { $0.id == fixture.suppliedText || $0.id == fixture.suppliedInnerText })
        XCTAssertTrue(hidden.nodes.contains { $0.id == customDefault }, "The default contents show again")
    }

    // SF-0903-003, OD-018 with OD-034: a Promo definition contains a Card
    // instance whose slot is filled inside Promo; a page Card instance holds
    // another Card in its slot. Both draw, with derived identities for the
    // content stored in Promo and canonical ones for page content, and a
    // missing definition inside a slot is one placeholder with no contents.
    func testSuppliedContentInsideDefinitionsAndSuppliedInstancesProjectAtEveryLevel() throws {
        var fixture = try suppliedCardFixture()
        var document = fixture.document
        let cardID = try XCTUnwrap(document.componentDefinitions.first?.id)
        func geometry(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [NodeProperty] {
            [("layout.x", x), ("layout.y", y), ("layout.width", width), ("layout.height", height)].map {
                .init(key: .init(rawValue: $0.0), value: .number($0.1), origin: .authored)
            }
        }
        // Fresh property identities each time: they are unique across a document.
        func marker() -> NodeProperty {
            .init(key: .init(rawValue: CanonicalComponentSlot.overrideKey(fixture.slotID)),
                  value: .string(CanonicalComponentSlot.suppliedValue), origin: .authored)
        }
        func membership() -> NodeProperty {
            .init(key: .init(rawValue: CanonicalComponentSlot.supplyKey), value: .string(fixture.slotID.description), origin: .authored)
        }
        // Promo contains a Card whose slot holds the Text "In Promo".
        let promoID = PageID(), promoRoot = NodeID(), promoCard = NodeID(), promoText = NodeID()
        document.pages.append(DocumentPage(id: promoID, name: "Promo", route: .init(rawValue: ""), role: .componentDefinition,
            provenance: .authored, rootNodeIDs: [promoRoot], nodes: [
                DocumentNode(id: promoRoot, kind: .frame, name: "Promo", parent: .page(promoID), childIDs: [promoCard],
                             properties: geometry(0, 0, 600, 400)),
                DocumentNode(id: promoCard, kind: .component, name: "Card", parent: .node(promoRoot), childIDs: [promoText],
                             properties: geometry(20, 30, 320, 240) + [
                                .init(key: .init(rawValue: CanonicalComponentReference.key), value: .string(cardID.description)), marker()]),
                DocumentNode(id: promoText, kind: .text, name: "In Promo", parent: .node(promoCard),
                             properties: geometry(0, 0, 100, 24) + [membership(), .init(key: .init(rawValue: "content.text"), value: .string("In Promo"))]),
            ]))
        let pageRoot = document.pages[0].rootNodeIDs[0]
        let promoInstance = DocumentNode(kind: .component, name: "Promo", parent: .node(pageRoot),
            properties: geometry(500, 500, 600, 400) + [.init(key: .init(rawValue: CanonicalComponentReference.key), value: .string(promoID.description))])
        // The Inherit card gets another Card (with an empty slot) and a missing component in its slot.
        let inheritIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == fixture.inherit })
        let cardInSlot = DocumentNode(kind: .component, name: "Card", parent: .node(fixture.inherit),
            properties: geometry(0, 0, 160, 90) + [.init(key: .init(rawValue: CanonicalComponentReference.key), value: .string(cardID.description)),
                membership(), .init(key: .init(rawValue: CanonicalComponentSlot.overrideKey(fixture.slotID)),
                                     value: .string(CanonicalComponentSlot.emptyValue), origin: .authored)])
        let missing = DocumentNode(kind: .component, name: "Gone", parent: .node(fixture.inherit),
            properties: geometry(0, 100, 50, 50) + [.init(key: .init(rawValue: CanonicalComponentReference.key), value: .string(PageID().description)),
                membership()])
        document.pages[0].nodes[inheritIndex].properties.append(marker())
        document.pages[0].nodes[inheritIndex].childIDs = [cardInSlot.id, missing.id]
        document.pages[0].nodes[0].childIDs.append(promoInstance.id)
        document.pages[0].nodes += [cardInSlot, missing, promoInstance]
        try document.validate()
        fixture.document = document

        let resolved = try ComponentGraphResolver.resolvedPage(document.pages[0], in: document, breakpoint: .desktop)
        let byID = Dictionary(uniqueKeysWithValues: resolved.nodes.map { ($0.id, $0) })
        XCTAssertEqual(Set(resolved.nodes.map(\.id)).count, resolved.nodes.count)
        let derivedCard = ComponentGraphResolver.derivedID(promoCard, in: promoInstance)
        let derivedCardNode = DocumentNode(id: derivedCard, kind: .component, name: "Card", parent: .node(promoInstance.id))
        let derivedText = ComponentGraphResolver.derivedID(promoText, in: promoInstance)
        let promoSlot = ComponentGraphResolver.derivedID(fixture.slotNodeID, in: derivedCardNode)
        XCTAssertEqual(byID[promoSlot]?.childIDs, [derivedText])
        XCTAssertEqual(byID[derivedText]?.insertionStringProperty("content.text"), "In Promo")
        XCTAssertEqual(byID[derivedText]?.insertionGeometry?.origin, WorldPoint(x: 500 + 20 + 16, y: 500 + 30 + 60))
        XCTAssertNil(byID[promoText], "Content stored in a definition is never drawn under its canonical identity")

        let inheritInstance = try XCTUnwrap(document.pages[0].nodes.first { $0.id == fixture.inherit })
        let inheritSlot = ComponentGraphResolver.derivedID(fixture.slotNodeID, in: inheritInstance)
        XCTAssertEqual(byID[inheritSlot]?.childIDs, [cardInSlot.id, missing.id])
        let slotCard = try XCTUnwrap(byID[cardInSlot.id])
        XCTAssertEqual(slotCard.kind, .frame, "The Card inside the slot expands too")
        XCTAssertEqual(byID[ComponentGraphResolver.derivedID(fixture.slotNodeID, in: cardInSlot)]?.childIDs, [],
                       "Its own empty slot")
        XCTAssertEqual(byID[missing.id]?.kind, .component)
        XCTAssertEqual(byID[missing.id]?.childIDs, [], "A missing component inside a slot is one placeholder")
        XCTAssertEqual(CanonicalComponentGraph.outputInstances(in: document).map(\.id).filter { $0 == missing.id }, [missing.id],
                       "Output recovery checks see the instance inside the slot")
    }

    /// SF-0903-003, OD-018 regression: a copy's slot contents are
    /// laid out after projection, never by the page's own automatic-sizing
    /// pass. With a hug-height slot item, and with the copy placed by an
    /// auto-height Stack, the contents still draw at the slot origin plus their
    /// slot-local offsets, and the stored slot-local values are unchanged.
    func testSlotContentsKeepSlotLocalPositionsWhenThePageUsesAutomaticSizing() throws {
        let fixture = try suppliedCardFixture()
        func hugHeight() -> NodeProperty {
            .init(key: .init(rawValue: CanonicalSizingConstraints.prefix + "heightMode"),
                  value: .string(CanonicalSizingMode.hug.rawValue), origin: .authored)
        }
        // Drawn origins after projection and after the resolved page's own
        // layout pass (the canvas and export path).
        func drawn(_ ids: [NodeID], in document: CanonicalDocument) throws -> [WorldPoint?] {
            let resolved = try ComponentGraphResolver.resolvedPage(document.pages[0], in: document, breakpoint: .desktop)
            let laidOut = resolved.resolvedStructuralGeometry(breakpoint: .desktop)
            return ids.map { laidOut[$0]?.origin }
        }
        let contents = [fixture.suppliedText, fixture.suppliedInnerText]

        // 1. A hug-height item makes the page use automatic sizing.
        var hugging = fixture.document
        let textIndex = try XCTUnwrap(hugging.pages[0].nodes.firstIndex { $0.id == fixture.suppliedText })
        hugging.pages[0].nodes[textIndex].properties.append(hugHeight())
        try hugging.validate()
        XCTAssertEqual(try drawn(contents, in: hugging),
                       [WorldPoint(x: 40 + 16 + 8, y: 60 + 60 + 4), WorldPoint(x: 40 + 16 + 100, y: 60 + 60 + 40)])
        let stored = hugging.pages[0].resolvedStructuralGeometry(breakpoint: .desktop)
        XCTAssertEqual(stored[fixture.suppliedText]?.origin, WorldPoint(x: 8, y: 4), "Still slot-local in the page pass")

        // 2. The copy sits in a hug-height Stack that places it.
        var stacked = fixture.document
        let pageRoot = stacked.pages[0].rootNodeIDs[0]
        let rootIndex = try XCTUnwrap(stacked.pages[0].nodes.firstIndex { $0.id == pageRoot })
        let customIndex = try XCTUnwrap(stacked.pages[0].nodes.firstIndex { $0.id == fixture.custom })
        let stack = DocumentNode(kind: .stack, name: "Stack", parent: .node(pageRoot), childIDs: [fixture.custom],
            properties: [("layout.x", 700.0), ("layout.y", 800.0), ("layout.width", 400.0), ("layout.height", 300.0),
                         ("layout.padding", 24.0), ("layout.gap", 24.0)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1), origin: .authored)
            } + [("layout.container.kind", "stack"), ("layout.axis", "vertical"), ("layout.align", "start")].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .string($0.1), origin: .defaulted)
            } + [hugHeight()])
        stacked.pages[0].nodes[rootIndex].childIDs.removeAll { $0 == fixture.custom }
        stacked.pages[0].nodes[rootIndex].childIDs.append(stack.id)
        stacked.pages[0].nodes[customIndex].parent = .node(stack.id)
        stacked.pages[0].nodes.append(stack)
        try stacked.validate()
        let placed = try XCTUnwrap(stacked.pages[0].resolvedStructuralGeometry(breakpoint: .desktop)[fixture.custom]?.origin)
        XCTAssertNotEqual(placed, WorldPoint(x: 40, y: 60), "The Stack places the copy")
        XCTAssertEqual(try drawn(contents, in: stacked),
                       [WorldPoint(x: placed.x + 16 + 8, y: placed.y + 60 + 4), WorldPoint(x: placed.x + 16 + 100, y: placed.y + 60 + 40)],
                       "Slot contents follow the copy exactly once")
        let item = try XCTUnwrap(stacked.pages[0].nodes.first { $0.id == fixture.suppliedText })
        XCTAssertFalse(CanonicalSizingConstraints.isLayoutResolved(.x, node: item, page: stacked.pages[0],
                                                                   breakpoint: .desktop, width: nil),
                       "The Stack outside the copy does not position its slot items, so they stay movable")
    }

    /// OD-033 fixture: a Button definition (root Frame 200 × 48 with radius 8,
    /// Text "Label" "Buy") with Size (Small default, Large) and Tone (Primary
    /// default, Secondary). Large: text "Buy now" and label width 160.
    /// Secondary: opacity 0.5 and no radius. Large + Secondary: text
    /// "Buy now, save". One copy per entry of `copies` on Home, choosing Large
    /// and/or Secondary as listed (nothing chosen otherwise).
    private func variantButtonDocument(copies: [(large: Bool, secondary: Bool)]) throws
        -> (document: CanonicalDocument, copies: [NodeID], labelID: NodeID, definitionID: PageID) {
        typealias V = CanonicalComponentVariants
        func number(_ key: String, _ value: Double) -> NodeProperty { .init(key: .init(rawValue: key), value: .number(value)) }
        func string(_ key: String, _ value: String) -> NodeProperty { .init(key: .init(rawValue: key), value: .string(value)) }
        func frame(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [NodeProperty] {
            [number("layout.x", x), number("layout.y", y), number("layout.width", width), number("layout.height", height)]
        }
        var document = ProjectCreation.blank()
        let definitionID = PageID(), rootID = NodeID(), labelID = NodeID()
        let size = ComponentVariantAxisID(), small = ComponentVariantValueID(), large = ComponentVariantValueID()
        let tone = ComponentVariantAxisID(), primary = ComponentVariantValueID(), secondary = ComponentVariantValueID()
        let both = CanonicalVariantCombination([large, secondary])
        let radiusKey = DesignBoxStyleCommandRegistry.namespace + "radius.uniform"
        let rootProperties = frame(0, 0, 200, 48) + [number(radiusKey, 8),
            string(V.axesKey, "\(size),\(tone)"),
            string(V.axisKey(size, "name"), "Size"), string(V.axisKey(size, "values"), "\(small),\(large)"),
            string(V.axisKey(size, "default"), small.description),
            string(V.valueNameKey(small), "Small"), string(V.valueNameKey(large), "Large"),
            string(V.axisKey(tone, "name"), "Tone"), string(V.axisKey(tone, "values"), "\(primary),\(secondary)"),
            string(V.axisKey(tone, "default"), primary.description),
            string(V.valueNameKey(primary), "Primary"), string(V.valueNameKey(secondary), "Secondary"),
            number(V.overrideKey(.value(secondary), "style.opacity"), 0.5),
            .init(key: .init(rawValue: V.unsetKey(.value(secondary), radiusKey)), value: .boolean(true)),
        ]
        let labelProperties = frame(12, 12, 120, 24) + [string("content.text", "Buy"),
            string(V.overrideKey(.value(large), "content.text"), "Buy now"),
            number(V.overrideKey(.value(large), "layout.width"), 160),
            string(V.overrideKey(.combination(both), "content.text"), "Buy now, save"),
        ]
        document.pages.append(DocumentPage(id: definitionID, name: "Button", route: .init(rawValue: ""), role: .componentDefinition,
            provenance: .authored, rootNodeIDs: [rootID], nodes: [
                DocumentNode(id: rootID, kind: .frame, name: "Button", parent: .page(definitionID), childIDs: [labelID],
                             properties: rootProperties),
                DocumentNode(id: labelID, kind: .text, name: "Label", parent: .node(rootID), properties: labelProperties),
            ]))
        let pageRoot = document.pages[0].rootNodeIDs[0]
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == pageRoot })
        var ids: [NodeID] = []
        for (index, choice) in copies.enumerated() {
            var properties = frame(Double(index % 50) * 220, 60 + Double(index / 50) * 60, 200, 48)
                + [string(CanonicalComponentReference.key, definitionID.description)]
            if choice.large { properties.append(string(V.choiceKey(size), large.description)) }
            if choice.secondary { properties.append(string(V.choiceKey(tone), secondary.description)) }
            let copy = DocumentNode(kind: .component, name: "Button", parent: .node(pageRoot), properties: properties)
            ids.append(copy.id)
            document.pages[0].nodes.append(copy)
        }
        document.pages[0].nodes[rootIndex].childIDs += ids
        return (document, ids, labelID, definitionID)
    }

    // SF-0904-003, SF-1204-003, OD-033: each copy draws the variant it chose,
    // identically on the canvas, in the in-app Preview and in the exported
    // site: text, child size, opacity and a radius one variant removes. A
    // component placed inside another keeps its own variant choice.
    func testComponentVariantsDrawOnCanvasPreviewAndExportIdentically() async throws {
        let built = try variantButtonDocument(copies: [(false, false), (true, false), (true, true)])
        var document = built.document
        try document.validate()
        let viewport = try CanvasViewportState(viewportSize: .init(width: 1200, height: 800),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1440, height: 900)), pixelRatio: .init(2))
        let prepared = try await WorkspaceScenePreparationWorker().prepare(.init(document: document,
            activePageID: document.pages[0].id, activeContainerID: nil, viewport: viewport, surfaceID: CanvasRenderSurfaceID()))
        func label(_ copyID: NodeID) throws -> CanvasRenderObject {
            let copy = try XCTUnwrap(document.pages[0].nodes.first { $0.id == copyID })
            let id = ComponentGraphResolver.derivedID(built.labelID, in: copy)
            return try XCTUnwrap(prepared.renderScene.objects.first { $0.id == id })
        }
        func root(_ copyID: NodeID) throws -> CanvasRenderObject {
            try XCTUnwrap(prepared.renderScene.objects.first { $0.id == copyID })
        }
        XCTAssertEqual(try label(built.copies[0]).plainText, "Buy")
        XCTAssertEqual(try label(built.copies[1]).plainText, "Buy now")
        XCTAssertEqual(try label(built.copies[2]).plainText, "Buy now, save")
        XCTAssertEqual(try label(built.copies[0]).frame.size.width, 120)
        XCTAssertEqual(try label(built.copies[1]).frame.size.width, 160, "Large widens the label")
        XCTAssertEqual(try root(built.copies[0]).cornerRadius, 8)
        XCTAssertEqual(try root(built.copies[2]).cornerRadius, 0, "Secondary removes the radius")
        XCTAssertEqual(try root(built.copies[2]).opacity, 0.5)
        XCTAssertEqual(try root(built.copies[1]).opacity, 1)

        let plan = try MultiPageStaticBuildPlanner.plan(document: document)
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        for text in [">Buy<", ">Buy now<", ">Buy now, save<"] {
            XCTAssertEqual(html.components(separatedBy: text).count - 1, 1, "\(text): \(html)")
        }
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        func rule(_ id: NodeID) -> String {
            let selector = CanonicalCSSRule.selector(for: id) + " { "
            return css.split(separator: "\n").map(String.init).filter { $0.hasPrefix(selector) }.joined(separator: "\n")
        }
        XCTAssertTrue(rule(built.copies[0]).contains("border-radius: 8.0px;"), css)
        XCTAssertFalse(rule(built.copies[2]).contains("border-radius"), css)
        XCTAssertTrue(rule(built.copies[2]).contains("opacity: 0.5;"), css)
        XCTAssertFalse(css.contains(CanonicalComponentVariants.namespace), "Variant data never reaches output")
        XCTAssertFalse(html.contains(CanonicalComponentVariants.namespace))

        let preview = try await LocalPreviewRuntimeCompiler().compile(document: document, imageResourceData: [:],
                                                                      pixelRatio: CanvasPixelRatio(1))
        let home = try XCTUnwrap(preview.pages.first { $0.id == document.pages[0].id })
        XCTAssertEqual(Set(home.objects.compactMap(\.plainText)).intersection(["Buy", "Buy now", "Buy now, save"]).count, 3)
        for copyID in built.copies {
            let previewRoot = try XCTUnwrap(home.objects.first { $0.id == copyID })
            XCTAssertEqual(previewRoot.opacity, try root(copyID).opacity)
            XCTAssertEqual(previewRoot.cornerRadius, try root(copyID).cornerRadius)
        }

        // A Card definition containing a Button that chose Large: copies of
        // the Card draw the inner Button's own variant.
        typealias V = CanonicalComponentVariants
        let buttonDefinition = try XCTUnwrap(document.componentDefinitions.first)
        let set = try XCTUnwrap(V.variantSet(in: buttonDefinition))
        let cardID = PageID(), cardRoot = NodeID(), innerButton = NodeID()
        func geometry(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [NodeProperty] {
            [("layout.x", x), ("layout.y", y), ("layout.width", width), ("layout.height", height)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
            }
        }
        document.pages.append(DocumentPage(id: cardID, name: "Card", route: .init(rawValue: ""), role: .componentDefinition,
            provenance: .authored, rootNodeIDs: [cardRoot], nodes: [
                DocumentNode(id: cardRoot, kind: .frame, name: "Card", parent: .page(cardID), childIDs: [innerButton],
                             properties: geometry(0, 0, 320, 200)),
                DocumentNode(id: innerButton, kind: .component, name: "Button", parent: .node(cardRoot),
                             properties: geometry(20, 20, 200, 48) + [
                                .init(key: .init(rawValue: CanonicalComponentReference.key), value: .string(built.definitionID.description)),
                                .init(key: .init(rawValue: V.choiceKey(set.axes[0].id)), value: .string(set.axes[0].values[1].id.description))]),
            ]))
        let pageRoot = document.pages[0].rootNodeIDs[0]
        let cardCopy = DocumentNode(kind: .component, name: "Card", parent: .node(pageRoot),
            properties: geometry(800, 400, 320, 200) + [.init(key: .init(rawValue: CanonicalComponentReference.key),
                                                              value: .string(cardID.description))])
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == pageRoot })
        document.pages[0].nodes[rootIndex].childIDs.append(cardCopy.id)
        document.pages[0].nodes.append(cardCopy)
        try document.validate()
        let nested = try ComponentGraphResolver.resolvedPage(document.pages[0], in: document, breakpoint: .desktop)
        let innerInstance = DocumentNode(id: ComponentGraphResolver.derivedID(innerButton, in: cardCopy), kind: .component,
                                         name: "Button", parent: .node(cardCopy.id))
        let innerLabel = ComponentGraphResolver.derivedID(built.labelID, in: innerInstance)
        XCTAssertEqual(nested.nodes.first { $0.id == innerLabel }?.insertionStringProperty("content.text"), "Buy now")
    }

    // SF-0904-007, OD-033: resolving copies' variants and validating every
    // authored variant stay within safety bounds on the standard (about 100
    // objects), large (about 10,000) and stress (the 20,000-object budget)
    // fixtures, with copies spread across all four variants.
    func testComponentVariantsStayWithinBoundsOnStandardLargeAndStressFixtures() throws {
        executionTimeAllowance = 60
        continueAfterFailure = false
        let clock = ContinuousClock()
        for (copies, bound) in [(49, Duration.seconds(1)), (4_999, .seconds(10)), (9_990, .seconds(20))] {
            let choices = (0..<copies).map { (large: $0 % 2 == 1, secondary: $0 % 4 >= 2) }
            let built = try variantButtonDocument(copies: choices)
            var validated = false
            let validation = try clock.measure { try built.document.validate(); validated = true }
            XCTAssertTrue(validated)
            XCTAssertLessThan(validation, bound, "\(copies) copies: safety bound only; named-hardware timings belong in retained evidence")
            var nodes: [DocumentNode] = []
            let elapsed = try clock.measure {
                nodes = try ComponentGraphResolver.resolvedPage(built.document.pages[0], in: built.document, breakpoint: .desktop).nodes
            }
            XCTAssertLessThan(elapsed, bound, "\(copies) copies: safety bound only")
            XCTAssertLessThanOrEqual(nodes.count, ResolvedGraphPolicy.maximumNodes)
            let texts = Set(nodes.compactMap { $0.insertionStringProperty("content.text") })
            XCTAssertEqual(texts, ["Buy", "Buy now", "Buy now, save"], "\(copies) copies")
            XCTAssertFalse(nodes.contains { $0.properties.contains { $0.key.rawValue.hasPrefix(CanonicalComponentVariants.namespace) } })
        }
    }

    /// SF-0606 fixture: Home with a 1000-wide Frame (outside the page at
    /// Tablet and Mobile), a small Text with long text (cut off), two
    /// overlapping Texts, a 20 × 20 Button and a Text hidden on Mobile that
    /// still has its own Mobile width.
    private func responsiveAuditDocument() throws -> (document: CanonicalDocument, wide: NodeID, cut: NodeID, first: NodeID,
                                                      second: NodeID, button: NodeID, hidden: NodeID) {
        func number(_ key: String, _ value: Double) -> NodeProperty { .init(key: .init(rawValue: key), value: .number(value)) }
        func string(_ key: String, _ value: String) -> NodeProperty { .init(key: .init(rawValue: key), value: .string(value)) }
        func frame(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [NodeProperty] {
            [number("layout.x", x), number("layout.y", y), number("layout.width", width), number("layout.height", height)]
        }
        var document = ProjectCreation.blank()
        let root = document.pages[0].rootNodeIDs[0]
        let wide = NodeID(), cut = NodeID(), first = NodeID(), second = NodeID(), button = NodeID(), hidden = NodeID()
        let nodes = [
            DocumentNode(id: wide, kind: .frame, name: "Wide", parent: .node(root), properties: frame(0, 0, 1_000, 100)),
            DocumentNode(id: cut, kind: .text, name: "Cut", parent: .node(root), properties: frame(20, 200, 60, 20)
                + [string("content.text", "This text is far too long to fit in this small box")]),
            DocumentNode(id: first, kind: .text, name: "First", parent: .node(root), properties: frame(20, 300, 100, 24)
                + [string("content.text", "First")]),
            DocumentNode(id: second, kind: .text, name: "Second", parent: .node(root), properties: frame(60, 310, 100, 24)
                + [string("content.text", "Second")]),
            DocumentNode(id: button, kind: .button, name: "Go", parent: .node(root), properties: frame(20, 400, 20, 20)
                + [string("content.text", "Go")]),
            DocumentNode(id: hidden, kind: .text, name: "Hidden", parent: .node(root), properties: frame(20, 500, 100, 24) + [
                string("content.text", "Hidden"), .init(key: .init(rawValue: ResponsiveVisibilityResolver.key(.mobile)), value: .boolean(false)),
                number(ResponsiveGeometryResolver.key(.width, breakpoint: .mobile), 80)]),
        ]
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == root })
        document.pages[0].nodes[rootIndex].childIDs += nodes.map(\.id)
        document.pages[0].nodes += nodes
        try document.validate()
        return (document, wide, cut, first, second, button, hidden)
    }

    // SF-0606-001/003/004: the audit samples Desktop, Tablet and Mobile from
    // what the canvas draws and reports each kind of problem with its exact
    // width, identity and measurement: content outside the page only where it
    // is, text that doesn't fit, overlapping content, a small tap target and a
    // breakpoint setting on an object hidden there. A suppressed kind stays
    // listed but inactive, the suppression is stored in the project as one
    // undoable change, and the report belongs to its revision.
    @MainActor
    func testResponsiveAuditReportsEachKindAtItsExactWidthAndHonorsSuppression() async throws {
        let built = try responsiveAuditDocument()
        XCTAssertEqual(ResponsiveAuditSample.standard.map(\.width),
                       [ViewportPreset.desktop, .tablet, .mobile].map { Double($0.width) }, "Samples match the canvas presets")
        let report = try await ResponsiveAuditRunner.run(document: built.document, pageID: built.document.pages[0].id)
        XCTAssertEqual(report.revision, built.document.revision)
        func findings(_ kind: ResponsiveAuditFindingKind, _ node: NodeID) -> [ResponsiveAuditFinding] {
            report.findings.filter { $0.kind == kind && $0.nodeID == node }
        }
        let overflow = findings(.overflow, built.wide)
        XCTAssertEqual(Set(overflow.map(\.sample.breakpoint)), [.tablet, .mobile], "Inside the page at Desktop")
        let tablet = try XCTUnwrap(overflow.first { $0.sample.breakpoint == .tablet })
        let mobile = try XCTUnwrap(overflow.first { $0.sample.breakpoint == .mobile })
        XCTAssertGreaterThan(mobile.measure, tablet.measure)
        XCTAssertTrue(tablet.explanation.contains("768 pt wide"))
        XCTAssertEqual(findings(.truncation, built.cut).count, 3)
        XCTAssertGreaterThan(try XCTUnwrap(findings(.truncation, built.cut).first).measure, 20)
        let collision = try XCTUnwrap(findings(.collision, built.first).first { $0.sample.breakpoint == .desktop }
                                      ?? findings(.collision, built.second).first { $0.sample.breakpoint == .desktop })
        XCTAssertEqual(Set([collision.nodeID, collision.otherNodeID]), Set([built.first, built.second]))
        XCTAssertEqual(collision.measure, 60 * 14, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(findings(.tapTarget, built.button).first).measure, 20, accuracy: 0.5)
        XCTAssertEqual(findings(.unreachableOverride, built.hidden).map(\.sample.breakpoint), [.mobile])
        XCTAssertTrue(report.findings.allSatisfy { !$0.isSuppressed })
        XCTAssertEqual(Set(report.findings.map(\.id)).count, report.findings.count, "Each finding has one stable identity")

        let session = DocumentSession(document: built.document)
        let command = try ResponsiveAuditSuppressionRegistry().prepare(nodeID: collision.nodeID, pageID: collision.pageID,
            kind: .collision, suppressed: true, expectedDocumentID: session.document.id, expectedRevision: session.document.revision,
            document: session.document, isLifecycleAvailable: true)
        try session.execute(command)
        let suppressed = try await ResponsiveAuditRunner.run(document: session.document, pageID: session.document.pages[0].id)
        XCTAssertTrue(suppressed.findings.filter { $0.kind == .collision }.allSatisfy(\.isSuppressed))
        XCTAssertFalse(suppressed.activeFindings.contains { $0.kind == .collision })
        XCTAssertEqual(suppressed.suppressedCount, suppressed.findings.filter { $0.kind == .collision }.count)
        XCTAssertNotEqual(suppressed.revision, report.revision)
        try session.undo()
        XCTAssertEqual(session.document.pages, built.document.pages)
    }

    // SF-0606-007: auditing three widths stays within safety bounds on the
    // standard (about 100 objects) and large (about 10,000 objects) fixtures.
    func testResponsiveAuditStaysWithinBoundsOnStandardAndLargeFixtures() async throws {
        executionTimeAllowance = 180
        continueAfterFailure = false
        let clock = ContinuousClock()
        for (count, bound) in [(100, Duration.seconds(10)), (10_000, .seconds(120))] {
            var document = ProjectCreation.blank()
            let root = document.pages[0].rootNodeIDs[0]
            let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == root })
            for index in 0..<count {
                let node = DocumentNode(kind: .text, name: "Item \(index)", parent: .node(root), properties:
                    [("layout.x", Double(index % 40) * 30), ("layout.y", Double(index / 40) * 30), ("layout.width", 28), ("layout.height", 28)]
                        .map { NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1)) }
                    + [NodeProperty(key: .init(rawValue: "content.text"), value: .string("\(index)"))])
                document.pages[0].nodes[rootIndex].childIDs.append(node.id)
                document.pages[0].nodes.append(node)
            }
            let pageID = document.pages[0].id
            var report: ResponsiveAuditReport?
            let started = clock.now
            report = try await ResponsiveAuditRunner.run(document: document, pageID: pageID)
            XCTAssertLessThan(started.duration(to: clock.now), bound, "\(count) objects: safety bound only")
            XCTAssertEqual(report?.samples.count, 3)
            XCTAssertFalse(report?.findings.contains { $0.kind == .collision } ?? true, "\(count): a tidy grid has no overlaps")
        }
    }

    // SF-0606-003 (lane V04 regression): the scene's clip always includes the
    // page bounds, so overflow is measured against the page sides with only
    // content-clipping ancestors applied. A child its clipping parent hides
    // entirely is not reported; without the clip it is, with its exact width.
    func testResponsiveAuditOverflowIgnoresThePageClipAndHonorsClippingParents() async throws {
        var document = ProjectCreation.blank()
        let root = document.pages[0].rootNodeIDs[0]
        func frame(_ name: String, parent: NodeID, x: Double, width: Double) -> DocumentNode {
            .init(kind: .frame, name: name, parent: .node(parent), properties: [
                .init(key: .init(rawValue: "layout.x"), value: .number(x)),
                .init(key: .init(rawValue: "layout.y"), value: .number(80)),
                .init(key: .init(rawValue: "layout.width"), value: .number(width)),
                .init(key: .init(rawValue: "layout.height"), value: .number(120))])
        }
        let clipKey = DesignBoxStyleCommandRegistry.namespace + "clip.content"
        var parent = frame("Clipper", parent: root, x: 0, width: 300)
        let child = frame("Clipped", parent: parent.id, x: 500, width: 100)
        parent.childIDs = [child.id]
        parent.properties.append(.init(key: .init(rawValue: clipKey), value: .boolean(true)))
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == root })
        document.pages[0].nodes[rootIndex].childIDs = [parent.id]
        document.pages[0].nodes += [parent, child]
        try document.validate()
        let pageID = document.pages[0].id
        let clipped = try await ResponsiveAuditRunner.run(document: document, pageID: pageID)
        XCTAssertFalse(clipped.findings.contains { $0.kind == .overflow }, "Nothing visible is outside the page")

        let parentIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == parent.id })
        document.pages[0].nodes[parentIndex].properties.removeAll { $0.key.rawValue == clipKey }
        let unclipped = try await ResponsiveAuditRunner.run(document: document, pageID: pageID)
        let mobile = try XCTUnwrap(unclipped.findings.first {
            $0.kind == .overflow && $0.nodeID == child.id && $0.sample.breakpoint == .mobile
        })
        XCTAssertEqual(mobile.measure, 210, accuracy: 0.5, "600 − 390")
        XCTAssertFalse(unclipped.findings.contains { $0.kind == .overflow && $0.sample.breakpoint == .desktop })
    }

    /// SF-0605 fixture: a Card definition whose root Frame (300 × 120) is the
    /// query container "card". Its Text "Title" ("Hello", 12, 12, 200 × 24)
    /// has one rule: at least 400 pt → text size 28. Its Frame "Badge"
    /// (240, 12, 40 × 40) has one rule: at least 400 pt → width 120. Home has
    /// a narrow copy (300 wide) and a wide copy (500 wide).
    private func containerQueryCardDocument(hugRoot: Bool = false) throws
        -> (document: CanonicalDocument, narrow: NodeID, wide: NodeID, title: NodeID, badge: NodeID) {
        typealias Q = CanonicalContainerQueries
        func number(_ key: String, _ value: Double) -> NodeProperty { .init(key: .init(rawValue: key), value: .number(value)) }
        func string(_ key: String, _ value: String) -> NodeProperty { .init(key: .init(rawValue: key), value: .string(value)) }
        func frame(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [NodeProperty] {
            [number("layout.x", x), number("layout.y", y), number("layout.width", width), number("layout.height", height)]
        }
        var document = ProjectCreation.blank()
        let definitionID = PageID(), rootID = NodeID(), titleID = NodeID(), badgeID = NodeID()
        let titleRule = ContainerQueryRuleID(), badgeRule = ContainerQueryRuleID()
        var rootProperties = frame(0, 0, 300, 120) + [string(Q.containerKey, "card")]
        if hugRoot { rootProperties.append(string(CanonicalSizingConstraints.prefix + "widthMode", "hug")) }
        document.pages.append(DocumentPage(id: definitionID, name: "Card", route: .init(rawValue: ""), role: .componentDefinition,
            provenance: .authored, rootNodeIDs: [rootID], nodes: [
                DocumentNode(id: rootID, kind: .frame, name: "Card", parent: .page(definitionID), childIDs: [titleID, badgeID],
                             properties: rootProperties),
                DocumentNode(id: titleID, kind: .text, name: "Title", parent: .node(rootID), properties: frame(12, 12, 200, 24) + [
                    string("content.text", "Hello"), string(Q.rulesKey, titleRule.description),
                    number(Q.ruleKey(titleRule, "minWidth"), 400), number(Q.setKey(titleRule, CanonicalTypography.namespace + "size"), 28)]),
                DocumentNode(id: badgeID, kind: .frame, name: "Badge", parent: .node(rootID), properties: frame(240, 12, 40, 40) + [
                    string(Q.rulesKey, badgeRule.description),
                    number(Q.ruleKey(badgeRule, "minWidth"), 400), number(Q.setKey(badgeRule, "layout.width"), 120)]),
            ]))
        let pageRoot = document.pages[0].rootNodeIDs[0]
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == pageRoot })
        var copies: [NodeID] = []
        for (y, width) in [(0.0, 300.0), (200.0, 500.0)] {
            let copy = DocumentNode(kind: .component, name: "Card", parent: .node(pageRoot),
                                    properties: frame(0, y, width, 120) + [string(CanonicalComponentReference.key, definitionID.description)])
            copies.append(copy.id)
            document.pages[0].nodes.append(copy)
        }
        document.pages[0].nodes[rootIndex].childIDs += copies
        try document.validate()
        return (document, copies[0], copies[1], titleID, badgeID)
    }

    // SF-0605-003, SF-1204-003: each copy of a component follows the width
    // of its own container: the wide copy's title is larger and its badge
    // wider, the narrow copy is unchanged, identically on the canvas, in the
    // in-app Preview and in the exported site (`@container` after every other
    // rule). A container whose width depends on its contents (Hug) is
    // skipped everywhere: no rule applies and export names no container.
    // Validation refuses a Hug width, so that fallback is a defensive gate
    // a valid document never reaches; it is checked on the resolved page.
    func testContainerQueriesFollowEachCopysContainerOnCanvasPreviewAndExport() async throws {
        let built = try containerQueryCardDocument()
        let document = built.document
        let viewport = try CanvasViewportState(viewportSize: .init(width: 1200, height: 800),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1440, height: 900)), pixelRatio: .init(2))
        let prepared = try await WorkspaceScenePreparationWorker().prepare(.init(document: document,
            activePageID: document.pages[0].id, activeContainerID: nil, viewport: viewport, surfaceID: CanvasRenderSurfaceID()))
        func derived(_ id: NodeID, in copyID: NodeID) throws -> NodeID {
            ComponentGraphResolver.derivedID(id, in: try XCTUnwrap(document.pages[0].nodes.first { $0.id == copyID }))
        }
        func object(_ id: NodeID, in copyID: NodeID, _ objects: [CanvasRenderObject]) throws -> CanvasRenderObject {
            let target = try derived(id, in: copyID)
            return try XCTUnwrap(objects.first { $0.id == target })
        }
        let objects = prepared.renderScene.objects
        XCTAssertEqual(try object(built.title, in: built.narrow, objects).typography?.size, CanonicalTypography.defaultValue.size)
        XCTAssertEqual(try object(built.title, in: built.wide, objects).typography?.size, 28, "500 pt container: the rule applies")
        XCTAssertEqual(try object(built.badge, in: built.narrow, objects).frame.size.width, 40)
        XCTAssertEqual(try object(built.badge, in: built.wide, objects).frame.size.width, 120)

        let preview = try await LocalPreviewRuntimeCompiler().compile(document: document, imageResourceData: [:],
                                                                      pixelRatio: CanvasPixelRatio(1))
        let home = try XCTUnwrap(preview.pages.first { $0.id == document.pages[0].id })
        XCTAssertEqual(try object(built.title, in: built.wide, home.objects).typography?.size, 28)
        XCTAssertEqual(try object(built.badge, in: built.wide, home.objects).frame.size.width, 120)
        XCTAssertEqual(try object(built.badge, in: built.narrow, home.objects).frame.size.width, 40)

        let plan = try MultiPageStaticBuildPlanner.plan(document: document)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        for copy in [built.narrow, built.wide] {
            XCTAssertTrue(css.contains(CanonicalCSSRule.selector(for: copy) + " { container-type: inline-size; container-name: sf-cq-card; }"), css)
            let title = CanonicalCSSRule.selector(for: try derived(built.title, in: copy))
            XCTAssertTrue(css.contains("@container (min-width: 400px) { \(title) { font-size: 28.0px; } }"), css)
            let badge = CanonicalCSSRule.selector(for: try derived(built.badge, in: copy))
            XCTAssertTrue(css.contains("@container (min-width: 400px) { \(badge) { width: 120.0px; } }"), css)
        }
        let firstContainerRule = try XCTUnwrap(css.range(of: "@container")?.lowerBound)
        let layoutRule = try XCTUnwrap(css.range(of: "display: block;")?.lowerBound)
        XCTAssertLessThan(layoutRule, firstContainerRule, "Container rules come after layout rules, so a match wins")
        XCTAssertFalse(css.contains(CanonicalContainerQueries.namespace))

        // Hug fallback (ADR-0031): a named container whose width depends on
        // its contents is skipped and reported. `CanonicalSizingConstraints
        // .isValid` refuses a Hug width on every object, and no variant,
        // override, breakpoint or rule can set a sizing mode, so a valid
        // document can't be built with one; the gate that canvas, Preview,
        // Inspector and export share (`isActiveContainer`) is checked on the
        // resolved page instead.
        XCTAssertThrowsError(try containerQueryCardDocument(hugRoot: true)) {
            XCTAssertEqual($0 as? ModelValidationError, .invalidSizingConstraints)
        }
        let resolved = try ComponentGraphResolver.resolvedPage(document.pages[0], in: document, breakpoint: .desktop)
        let wideTitle = try derived(built.title, in: built.wide)
        XCTAssertNotNil(CanonicalContainerQueries.evaluated(resolved, breakpoint: .desktop).evaluation.winners[wideTitle])
        var hugging = resolved
        for copy in [built.narrow, built.wide] {
            let index = try XCTUnwrap(hugging.nodes.firstIndex { $0.id == copy })
            XCTAssertTrue(CanonicalContainerQueries.isActiveContainer(hugging.nodes[index]))
            hugging.nodes[index].properties.append(NodeProperty(
                key: .init(rawValue: CanonicalSizingConstraints.prefix + "widthMode"), value: .string("hug")))
            XCTAssertFalse(CanonicalContainerQueries.isActiveContainer(hugging.nodes[index]), "Export names no container")
        }
        let evaluation = CanonicalContainerQueries.evaluated(hugging, breakpoint: .desktop).evaluation
        XCTAssertNil(evaluation.winners[wideTitle], "No rule applies")
        XCTAssertNil(evaluation.statuses[wideTitle]?.first?.containerID)
        XCTAssertTrue(evaluation.findings.contains(.containerHugs(containerID: built.wide)))
        XCTAssertTrue(evaluation.findings.contains { $0.code == "container-query-no-container" })
    }

    // SF-0606-003 (lane V14a): Preview and the responsive audit place a fixed
    // object from the browser viewport's top-left corner, which is the page's,
    // so it shows where the exported page shows it and isn't reported as
    // running off the page (the editor's default scroll origin is (-128, -96)).
    func testPreviewAndResponsiveAuditPlaceFixedObjectsFromThePageCorner() async throws {
        let pageID = PageID(), rootID = NodeID(), badgeID = NodeID(), barID = NodeID()
        func property(_ key: String, _ value: PropertyValue) -> NodeProperty { .init(key: .init(rawValue: key), value: value) }
        func frame(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [NodeProperty] {
            [property("layout.x", .number(x)), property("layout.y", .number(y)),
             property("layout.width", .number(width)), property("layout.height", .number(height))]
        }
        let position = CanonicalPositioning.namespace
        let page = DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home, rootNodeIDs: [rootID], nodes: [
            DocumentNode(id: rootID, kind: .frame, name: "Page", parent: .page(pageID), childIDs: [badgeID, barID],
                         properties: frame(0, 0, 320, 1600)),
            DocumentNode(id: badgeID, kind: .frame, name: "Badge", parent: .node(rootID), properties: frame(200, 300, 80, 40) + [
                property(position + "mode", .string("fixed")), property(position + "left", .number(16)),
                property(position + "top", .number(20))]),
            DocumentNode(id: barID, kind: .frame, name: "Bar", parent: .node(rootID), properties: frame(0, 1200, 120, 40) + [
                property(position + "mode", .string("fixed")), property(position + "right", .number(10)),
                property(position + "bottom", .number(10))]),
        ])
        let document = CanonicalDocument(pages: [page])
        try document.validate()
        let preview = try await LocalPreviewRuntimeCompiler().compile(document: document, imageResourceData: [:],
                                                                      pixelRatio: CanvasPixelRatio(1), viewportWidth: 390)
        let objects = try XCTUnwrap(preview.pages.first).objects
        let badge = try XCTUnwrap(objects.first { $0.id == badgeID })
        XCTAssertEqual(badge.frame.origin.x, 16)
        XCTAssertEqual(badge.frame.origin.y, 20)
        let bar = try XCTUnwrap(objects.first { $0.id == barID })
        XCTAssertEqual(bar.frame.origin.x, 390 - 10 - 120, "Right edge of the 390 pt viewport")
        XCTAssertEqual(bar.frame.origin.y, 900 - 10 - 40, "Bottom edge of the 900 pt viewport")
        let report = try await ResponsiveAuditRunner.run(document: document, pageID: pageID)
        XCTAssertFalse(report.findings.contains { $0.kind == .overflow && [badgeID, barID].contains($0.nodeID) }, "\(report.findings)")
    }

    // SF-0601-003 / SF-0603-003 (lane V14a): a static-layout page writes each
    // object as its own element, so a hidden Frame's contents and Text (whose
    // typography rule sets `display` at higher specificity) need their own
    // hiding rule, written only for the breakpoints where the canvas hides them.
    func testStaticLayoutExportHidesObjectsContentsAndTextOnlyWhereHidden() throws {
        let pageID = PageID(), rootID = NodeID(), panelID = NodeID(), captionID = NodeID(), noteID = NodeID(), goneID = NodeID()
        func property(_ key: String, _ value: PropertyValue) -> NodeProperty { .init(key: .init(rawValue: key), value: value) }
        func frame(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [NodeProperty] {
            [property("layout.x", .number(x)), property("layout.y", .number(y)),
             property("layout.width", .number(width)), property("layout.height", .number(height))]
        }
        let page = DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home, rootNodeIDs: [rootID], nodes: [
            DocumentNode(id: rootID, kind: .frame, name: "Page", parent: .page(pageID), childIDs: [panelID, noteID, goneID],
                         properties: frame(0, 0, 1200, 900)),
            DocumentNode(id: panelID, kind: .frame, name: "Panel", parent: .node(rootID), childIDs: [captionID],
                         properties: frame(40, 40, 400, 300) + [property(ResponsiveVisibilityResolver.key(.mobile), .boolean(false))]),
            DocumentNode(id: captionID, kind: .text, name: "Caption", parent: .node(panelID),
                         properties: frame(8, 8, 200, 24) + [property("content.text", .string("Inside the panel"))]),
            DocumentNode(id: noteID, kind: .text, name: "Note", parent: .node(rootID), properties: frame(40, 400, 200, 24) + [
                property("content.text", .string("Phones and tablets")), property("hidden", .boolean(true)),
                property(ResponsiveVisibilityResolver.key(.tablet), .boolean(true)),
                property(ResponsiveVisibilityResolver.key(.mobile), .boolean(true))]),
            DocumentNode(id: goneID, kind: .text, name: "Gone", parent: .node(rootID), properties: frame(40, 480, 200, 24) + [
                property("content.text", .string("Never shown")), property("hidden", .boolean(true))]),
        ])
        let document = CanonicalDocument(pages: [page])
        try document.validate()
        XCTAssertFalse(page.usesConnectedOutput)
        let plan = try MultiPageStaticBuildPlanner.plan(document: document)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        let lines = css.components(separatedBy: "\n")
        func hide(_ id: NodeID) -> String { CanonicalCSSRule.selector(for: id) + "[data-siteforge-node] { display:none; }" }
        XCTAssertTrue(lines.contains(hide(goneID)), "Hidden everywhere: one rule without a condition")
        let phones = try XCTUnwrap(lines.first { $0.hasPrefix("@media (width < 600px) { ") && $0.contains(hide(panelID)) }, css)
        XCTAssertTrue(phones.contains(hide(captionID)), "The panel's contents are separate elements and hide with it")
        XCTAssertFalse(phones.contains(hide(noteID)))
        XCTAssertFalse(phones.contains(hide(goneID)))
        XCTAssertTrue(lines.contains("@media (min-width: 1024px) { \(hide(noteID)) }"), "Only desktop widths hide the note")
        XCTAssertFalse(lines.contains(hide(noteID)))
        XCTAssertFalse(css.contains("(width < 1024px) { \(hide(noteID))"))
        XCTAssertFalse(css.contains(hide(rootID)))
        // Same specificity as the text's own display rule, so the hiding rule comes later.
        let textDisplay = try XCTUnwrap(css.range(of: CanonicalCSSRule.selector(for: captionID) + "[data-siteforge-node] { display:flex")?.lowerBound)
        let phoneHiding = try XCTUnwrap(css.range(of: phones)?.lowerBound)
        XCTAssertLessThan(textDisplay, phoneHiding)
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        XCTAssertTrue(html.contains("Inside the panel"), "Hiding is styling; the text stays in the page")
        XCTAssertTrue(html.contains("<link rel=\"stylesheet\" href=\"styles.css\">"), "The hiding rules reach the page")
    }

    // SF-0605-007: evaluating container queries stays within safety bounds on
    // the standard, large and stress fixtures (copies with two rules each).
    func testContainerQueriesStayWithinBoundsOnStandardLargeAndStressFixtures() throws {
        executionTimeAllowance = 60
        continueAfterFailure = false
        let clock = ContinuousClock()
        let base = try containerQueryCardDocument().document
        for (copies, bound) in [(33, Duration.seconds(1)), (3_300, .seconds(10)), (6_600, .seconds(20))] {
            var document = base
            let pageRoot = document.pages[0].rootNodeIDs[0]
            let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == pageRoot })
            let template = try XCTUnwrap(document.pages[0].nodes.last)
            for index in 0..<copies {
                var copy = DocumentNode(kind: .component, name: "Card \(index)", parent: .node(pageRoot), properties: template.properties
                    .filter { !["layout.x", "layout.y", "layout.width"].contains($0.key.rawValue) }
                    .map { NodeProperty(key: $0.key, value: $0.value, origin: $0.origin) })
                copy.properties += [("layout.x", Double(index % 10) * 520), ("layout.y", Double(index / 10) * 140),
                                    ("layout.width", index % 2 == 0 ? 300 : 500)].map {
                    NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
                }
                document.pages[0].nodes[rootIndex].childIDs.append(copy.id)
                document.pages[0].nodes.append(copy)
            }
            let resolved = try ComponentGraphResolver.resolvedPage(document.pages[0], in: document, breakpoint: .desktop)
            var evaluation = ContainerQueryEvaluation.empty
            let elapsed = clock.measure {
                evaluation = CanonicalContainerQueries.evaluated(resolved, breakpoint: .desktop).evaluation
            }
            XCTAssertLessThan(elapsed, bound, "\(copies) copies: safety bound only; named-hardware timings belong in retained evidence")
            XCTAssertEqual(evaluation.winners.count, (copies / 2 + 1) * 2, "\(copies): title and badge of every wide copy")
        }
    }

    // SF-0903-007, OD-018: projection stays within safety bounds and the shared
    // budget on the standard (101 objects drawn), large (10,001) and stress
    // (16,606 drawn; 19,927 counted against the 20,000 budget, which counts
    // supplied objects and full default contents before anything is allocated)
    // fixtures, every instance supplying its own contents. Cancellation is honored.
    func testSuppliedSlotProjectionStaysWithinBoundsOnStandardLargeAndStressFixtures() throws {
        executionTimeAllowance = 60
        continueAfterFailure = false
        let clock = ContinuousClock()
        for (instances, bound) in [(19, Duration.seconds(1)), (1_999, .seconds(5)), (3_320, .seconds(10))] {
            let document = try suppliedCardFixture(customInstances: instances).document
            var resolved: DocumentPage?
            let elapsed = try clock.measure {
                try document.validate()
                resolved = try ComponentGraphResolver.resolvedPage(document.pages[0], in: document, breakpoint: .desktop)
            }
            let nodes = try XCTUnwrap(resolved).nodes
            // Page root + per instance: Card root, slot Frame and 3 supplied objects (default removed),
            // plus Empty (2) and Inherit (3).
            XCTAssertEqual(nodes.count, 1 + instances * 5 + 2 + 3, "\(instances)")
            XCTAssertEqual(Set(nodes.map(\.id)).count, nodes.count)
            XCTAssertLessThan(elapsed, bound, "Safety bound only; named-hardware timings belong in retained evidence")
        }
        let over = try suppliedCardFixture(customInstances: 3_333).document
        XCTAssertThrowsError(try ComponentGraphResolver.resolvedPage(over.pages[0], in: over, breakpoint: .desktop)) {
            XCTAssertEqual($0 as? ComponentResolutionError, .objectLimitExceeded(ResolvedGraphPolicy.maximumNodes + 1))
        }
        var checks = 0
        let cancelled = try suppliedCardFixture(customInstances: 50).document
        XCTAssertThrowsError(try ComponentGraphResolver.resolvedPage(cancelled.pages[0], in: cancelled, breakpoint: .desktop,
            checkpoint: { checks += 1; if checks > 80 { throw CanvasRendererError.cancelled } })) {
            XCTAssertEqual($0 as? CanvasRendererError, .cancelled)
        }
    }

    private struct SuppliedCardFixture {
        var document: CanonicalDocument
        let slotID: ComponentSlotPropertyID, slotNodeID: NodeID, defaultTextID: NodeID
        let custom: NodeID, empty: NodeID, inherit: NodeID
        let suppliedText: NodeID, suppliedFrame: NodeID, suppliedInnerText: NodeID
    }

    /// OD-018 fixture. Card (320 × 240) has slot "Content": a Frame at (16, 60),
    /// 200 × 100, with default Text "Default". Page: `customInstances` Cards
    /// supplying Text "Custom" at slot-local (8, 4) (mobile x 2) and a Frame at
    /// (80, 20) holding Text "Inside" at (100, 40); then one Empty and one
    /// Inherit Card. The first custom Card sits at (40, 60).
    private func suppliedCardFixture(customInstances: Int = 1) throws -> SuppliedCardFixture {
        func geometry(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [NodeProperty] {
            [("layout.x", x), ("layout.y", y), ("layout.width", width), ("layout.height", height)].map {
                .init(key: .init(rawValue: $0.0), value: .number($0.1), origin: .authored)
            }
        }
        func text(_ value: String) -> NodeProperty { .init(key: .init(rawValue: "content.text"), value: .string(value)) }
        var document = CanonicalDocument()
        let cardID = PageID(), cardRoot = NodeID(), slotNode = NodeID(), defaultText = NodeID(), slotID = ComponentSlotPropertyID()
        document.pages.append(DocumentPage(id: cardID, name: "Card", route: .init(rawValue: ""), role: .componentDefinition,
            provenance: .authored, rootNodeIDs: [cardRoot], nodes: [
                DocumentNode(id: cardRoot, kind: .frame, name: "Card", parent: .page(cardID), childIDs: [slotNode],
                             properties: geometry(0, 0, 320, 240)),
                DocumentNode(id: slotNode, kind: .frame, name: "Content", parent: .node(cardRoot), childIDs: [defaultText],
                             properties: geometry(16, 60, 200, 100) + [
                                .init(key: .init(rawValue: CanonicalComponentSlot.namespace + "id"), value: .string(slotID.description), origin: .authored),
                                .init(key: .init(rawValue: CanonicalComponentSlot.namespace + "label"), value: .string("Content"), origin: .authored),
                                .init(key: .init(rawValue: CanonicalComponentSlot.namespace + "type"), value: .string("ordered-fallback-children"), origin: .authored)]),
                DocumentNode(id: defaultText, kind: .text, name: "Default", parent: .node(slotNode),
                             properties: geometry(16, 60, 120, 24) + [text("Default")]),
            ]))
        let pageRoot = document.pages[0].rootNodeIDs[0]
        func instance(_ index: Int) -> DocumentNode {
            DocumentNode(kind: .component, name: "Card", parent: .node(pageRoot),
                properties: geometry(40 + Double(index % 4) * 340, 60 + Double(index / 4) * 260, 320, 240)
                    + [.init(key: .init(rawValue: CanonicalComponentReference.key), value: .string(cardID.description))])
        }
        // Fresh property identities each time: they are unique across a document.
        func membership() -> NodeProperty {
            .init(key: .init(rawValue: CanonicalComponentSlot.supplyKey), value: .string(slotID.description), origin: .authored)
        }
        var nodes: [DocumentNode] = [], first: (NodeID, NodeID, NodeID, NodeID)?
        for index in 0..<customInstances {
            var card = instance(index)
            let suppliedText = DocumentNode(kind: .text, name: "Custom", parent: .node(card.id),
                properties: geometry(8, 4, 120, 24) + [membership(), text("Custom"),
                    .init(key: .init(rawValue: ResponsiveGeometryResolver.key(.x, breakpoint: .mobile)), value: .number(2), origin: .authored)])
            let innerText = DocumentNode(kind: .text, name: "Inside", parent: .node(NodeID()), properties: geometry(100, 40, 60, 20) + [text("Inside")])
            let frame = DocumentNode(kind: .frame, name: "Box", parent: .node(card.id), childIDs: [innerText.id],
                                     properties: geometry(80, 20, 100, 60) + [membership()])
            var inner = innerText; inner.parent = .node(frame.id)
            card.childIDs = [suppliedText.id, frame.id]
            card.properties.append(.init(key: .init(rawValue: CanonicalComponentSlot.overrideKey(slotID)),
                                         value: .string(CanonicalComponentSlot.suppliedValue), origin: .authored))
            nodes += [card, suppliedText, frame, inner]
            if first == nil { first = (card.id, suppliedText.id, frame.id, inner.id) }
        }
        var empty = instance(customInstances)
        empty.properties.append(.init(key: .init(rawValue: CanonicalComponentSlot.overrideKey(slotID)),
                                      value: .string(CanonicalComponentSlot.emptyValue), origin: .authored))
        let inherit = instance(customInstances + 1)
        nodes += [empty, inherit]
        let topLevel = nodes.filter { $0.parent == .node(pageRoot) }.map(\.id)
        document.pages[0].nodes[0].childIDs += topLevel
        document.pages[0].nodes += nodes
        let ids = try XCTUnwrap(first)
        return .init(document: document, slotID: slotID, slotNodeID: slotNode, defaultTextID: defaultText,
                     custom: ids.0, empty: empty.id, inherit: inherit.id,
                     suppliedText: ids.1, suppliedFrame: ids.2, suppliedInnerText: ids.3)
    }

    // SF-0901-003/005, SF-0905-003, SF-0510-003, OD-034: a Card whose
    // definition contains a Button instance draws, exports and previews the
    // Button with the value authored on it inside Card and with the Button's
    // linked box style. Objects inside the inner instance derive their
    // identity from the inner instance, so resolution is stable across
    // repeated resolution and save/reopen, on the page and in the definition.
    func testNestedComponentDrawsExportsAndKeepsItsOwnValuesWithStableDerivedIdentity() async throws {
        let fixture = try nestedButtonCardFixture()
        let document = fixture.document
        func derived(_ owner: NodeID, _ source: NodeID) -> NodeID {
            NodeID(DocumentPage.deterministicUUID(namespace: owner.rawValue, label: "component-child:" + source.description))
        }
        let innerRootID = derived(fixture.cardInstanceID, fixture.nestedInstanceID)
        let labelID = derived(innerRootID, fixture.labelID)

        let resolved = try ComponentGraphResolver.resolvedPage(document.pages[0], in: document, breakpoint: .desktop)
        XCTAssertEqual(resolved.nodes.count, 4, "Page root, Card root, Button root, Button label")
        XCTAssertEqual(Set(resolved.nodes.map(\.id)).count, 4)
        let innerRoot = try XCTUnwrap(resolved.nodes.first { $0.id == innerRootID })
        XCTAssertEqual(innerRoot.kind, .frame, "The inner instance resolves to its definition's root")
        XCTAssertEqual(innerRoot.parent, .node(fixture.cardInstanceID))
        XCTAssertEqual(innerRoot.childIDs, [labelID])
        XCTAssertEqual(CanonicalReusableStyleIndex.appliedIDs(innerRoot), [fixture.styleID])
        let label = try XCTUnwrap(resolved.nodes.first { $0.id == labelID })
        XCTAssertEqual(label.insertionStringProperty("content.text"), "Buy", "Value authored on the inner instance")
        XCTAssertEqual(try ComponentGraphResolver.resolvedPage(document.pages[0], in: document, breakpoint: .desktop), resolved)
        let reopened = try DocumentSerializer.decode(DocumentSerializer.encode(document))
        XCTAssertEqual(try ComponentGraphResolver.resolvedPage(reopened.pages[0], in: reopened, breakpoint: .desktop), resolved)

        // Editing Card shows the Button expanded under its canonical instance.
        let card = try XCTUnwrap(document.componentDefinitions.first { $0.id == fixture.cardID })
        let editing = try ComponentGraphResolver.resolvedPage(card, in: document, breakpoint: .desktop)
        XCTAssertEqual(editing.nodes.first { $0.id == fixture.nestedInstanceID }?.kind, .frame)
        XCTAssertEqual(editing.nodes.first { $0.id == derived(fixture.nestedInstanceID, fixture.labelID) }?
            .insertionStringProperty("content.text"), "Buy")

        let viewport = try CanvasViewportState(viewportSize: .init(width: 1200, height: 800),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1440, height: 900)), pixelRatio: .init(2))
        let prepared = try await WorkspaceScenePreparationWorker().prepare(.init(document: document,
            activePageID: document.pages[0].id, activeContainerID: nil, viewport: viewport, surfaceID: CanvasRenderSurfaceID()))
        let cardObject = try XCTUnwrap(prepared.renderScene.objects.first { $0.id == fixture.cardInstanceID })
        let buttonObject = try XCTUnwrap(prepared.renderScene.objects.first { $0.id == innerRootID })
        let labelObject = try XCTUnwrap(prepared.renderScene.objects.first { $0.id == labelID })
        XCTAssertEqual(buttonObject.border?.width, 2)
        XCTAssertEqual(buttonObject.cornerRadius, 8)
        XCTAssertEqual(labelObject.plainText, "Buy")
        XCTAssertEqual(buttonObject.frame.origin.x - cardObject.frame.origin.x, 16, accuracy: 0.001)
        XCTAssertEqual(buttonObject.frame.origin.y - cardObject.frame.origin.y, 140, accuracy: 0.001)
        XCTAssertEqual(labelObject.frame.origin.x - buttonObject.frame.origin.x, 12, accuracy: 0.001)
        XCTAssertEqual(labelObject.frame.size.width, 96, accuracy: 0.001)

        let plan = try MultiPageStaticBuildPlanner.plan(document: document)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        let selector = CanonicalCSSRule.selector(for: innerRootID) + " { "
        let rules = css.split(separator: "\n").map(String.init).filter { $0.hasPrefix(selector) }.joined(separator: "\n")
        XCTAssertTrue(rules.contains("border-radius: 8.0px;"), css)
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        XCTAssertTrue(html.contains("Buy"), html)
        XCTAssertFalse(html.contains(">Go<"), "The Button's own default is replaced by the authored value")
        let compiled = StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .development),
            resourceDescriptors: [:], resourceData: [:])
        XCTAssertNotNil(compiled.plan, "\(compiled.findings.map(\.code))")
        let preview = try await LocalPreviewRuntimeCompiler().compile(document: document, imageResourceData: [:],
                                                                      pixelRatio: CanvasPixelRatio(1))
        XCTAssertFalse(preview.pages.isEmpty)
    }

    // SF-0901-004, SF-0905-004, OD-034: inner instances whose definition is
    // missing stay placeholders and block Preview and export exactly like page
    // instances, each finding naming its own inner instance: one with an
    // authored value is an override conflict, one without is an unavailable
    // definition. A definition no page uses does not block output. A cyclic
    // graph held in memory still resolves (one level), so a repair can render.
    func testNestedMissingDefinitionBlocksPreviewAndExportAndCyclesStillResolve() async throws {
        var fixture = try nestedButtonCardFixture(buttonsPerCard: 2)
        let missingDefinitionID = fixture.buttonID
        fixture.document.pages.removeAll { $0.id == missingDefinitionID }
        let document = fixture.document
        try document.validate()
        let card = try XCTUnwrap(document.componentDefinitions.first { $0.id == fixture.cardID })
        let nested = card.nodes.filter { $0.kind == .component }.map(\.id)
        XCTAssertEqual(nested.count, 2)
        XCTAssertEqual(nested.first, fixture.nestedInstanceID, "The first inner instance carries the value Buy")
        let resolved = try ComponentGraphResolver.resolvedPage(document.pages[0], in: document, breakpoint: .desktop)
        for inner in nested {
            let placeholderID = NodeID(DocumentPage.deterministicUUID(namespace: fixture.cardInstanceID.rawValue,
                label: "component-child:" + inner.description))
            XCTAssertEqual(resolved.nodes.first { $0.id == placeholderID }?.kind, .component)
        }
        XCTAssertEqual(CanonicalComponentGraph.outputInstances(in: document).map(\.id), [fixture.cardInstanceID] + nested)
        let compiled = StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .development),
            resourceDescriptors: [:], resourceData: [:])
        XCTAssertNil(compiled.plan)
        XCTAssertTrue(compiled.findings.contains {
            $0.code == "component-override-conflict" && $0.requirementID == "SF-0905-004" && $0.affectedNodeID == nested[0]
        }, "\(compiled.findings.map(\.code))")
        XCTAssertTrue(compiled.findings.contains {
            $0.code == "component-definition-unavailable" && $0.requirementID == "SF-0901-004" && $0.affectedNodeID == nested[1]
        }, "\(compiled.findings.map(\.code))")
        XCTAssertFalse(compiled.findings.contains { $0.affectedNodeID == fixture.cardInstanceID },
                       "The outer instance itself resolves; only the inner links are broken")
        XCTAssertFalse(compiled.redactedSummary.contains("Buy"), "Findings never disclose authored values")
        do {
            _ = try await LocalPreviewRuntimeCompiler().compile(document: document, imageResourceData: [:],
                                                                pixelRatio: CanvasPixelRatio(1))
            XCTFail("Preview must not publish a missing inner definition")
        } catch { XCTAssertEqual(error as? LocalPreviewRuntimeError, .componentRecoveryRequired) }

        // The same broken Card, unused by any page, does not block output.
        var unused = document
        unused.pages[0].nodes[0].childIDs.removeAll { $0 == fixture.cardInstanceID }
        unused.pages[0].nodes.removeAll { $0.id == fixture.cardInstanceID }
        XCTAssertTrue(CanonicalComponentGraph.outputInstances(in: unused).isEmpty)
        XCTAssertNotNil(StaticBuildCompiler.compile(document: unused, profileSelection: .init(profile: .development),
            resourceDescriptors: [:], resourceData: [:]).plan)

        // Card ⇄ Button in memory (never saveable) still terminates.
        var cyclic = try nestedButtonCardFixture()
        let buttonIndex = try XCTUnwrap(cyclic.document.pages.firstIndex { $0.id == cyclic.buttonID })
        let buttonRootID = cyclic.document.pages[buttonIndex].rootNodeIDs[0]
        let back = DocumentNode(kind: .component, name: "Card", parent: .node(buttonRootID), properties:
            [("layout.x", 0.0), ("layout.y", 0.0), ("layout.width", 10.0), ("layout.height", 10.0)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
            } + [NodeProperty(key: .init(rawValue: CanonicalComponentReference.key), value: .string(cyclic.cardID.description))])
        cyclic.document.pages[buttonIndex].nodes[0].childIDs.append(back.id)
        cyclic.document.pages[buttonIndex].nodes.append(back)
        XCTAssertThrowsError(try cyclic.document.validate())
        let oneLevel = try ComponentGraphResolver.resolvedPage(cyclic.document.pages[0], in: cyclic.document,
                                                               breakpoint: .desktop)
        XCTAssertEqual(oneLevel.nodes.count, 3, "Page root, Card root and the unexpanded Button instance")
    }

    // SF-0901-007, OD-034: nested expansion stays inside the shared budget and
    // within safety bounds on the standard (106), large (9,997) and stress
    // (19,993) object fixtures; one Card more exceeds the budget before any
    // expansion is allocated, and cancellation is honored during expansion.
    func testNestedComponentExpansionStaysWithinBoundsOnStandardLargeAndStressFixtures() throws {
        executionTimeAllowance = 60
        continueAfterFailure = false
        let clock = ContinuousClock()
        for (cards, bound) in [(5, Duration.seconds(1)), (476, .seconds(5)), (952, .seconds(10))] {
            let fixture = try nestedButtonCardFixture(buttonsPerCard: 4, buttonParts: 3, cards: cards)
            let document = fixture.document
            let graph = CanonicalComponentGraph(document: document)
            // Button: root + label + 3 parts = 5; Card: root + 4 × 5 = 21.
            XCTAssertEqual(graph.expandedObjectCount(of: fixture.buttonID), 5)
            XCTAssertEqual(graph.expandedObjectCount(of: fixture.cardID), 21)
            var resolved: DocumentPage?
            let elapsed = try clock.measure {
                try document.validate()
                resolved = try ComponentGraphResolver.resolvedPage(document.pages[0], in: document, breakpoint: .desktop)
            }
            let nodes = try XCTUnwrap(resolved).nodes
            XCTAssertEqual(nodes.count, 1 + cards * 21)
            XCTAssertLessThanOrEqual(nodes.count, ResolvedGraphPolicy.maximumNodes)
            XCTAssertEqual(Set(nodes.map(\.id)).count, nodes.count, "Every derived identity is unique")
            // Safety bound only; named-hardware timings belong in retained evidence.
            XCTAssertLessThan(elapsed, bound, "\(cards) cards")
        }
        let over = try nestedButtonCardFixture(buttonsPerCard: 4, buttonParts: 3, cards: 953)
        XCTAssertThrowsError(try ComponentGraphResolver.resolvedPage(over.document.pages[0], in: over.document,
            breakpoint: .desktop)) {
            XCTAssertEqual($0 as? ComponentResolutionError, .objectLimitExceeded(ResolvedGraphPolicy.maximumNodes + 1))
        }
        var checks = 0
        let cancelled = try nestedButtonCardFixture(buttonsPerCard: 4, buttonParts: 3, cards: 50)
        XCTAssertThrowsError(try ComponentGraphResolver.resolvedPage(cancelled.document.pages[0], in: cancelled.document,
            breakpoint: .desktop, checkpoint: { checks += 1; if checks > 60 { throw CanvasRendererError.cancelled } })) {
            XCTAssertEqual($0 as? CanvasRendererError, .cancelled, "Cancellation is honored during expansion")
        }
    }

    private struct NestedButtonCardFixture {
        var document: CanonicalDocument
        let buttonID: PageID, cardID: PageID, styleID: ReusableStyleID
        let labelID: NodeID, nestedInstanceID: NodeID, cardInstanceID: NodeID
    }

    /// OD-034 fixture. Button (120 × 40, linked box style "Pill": 2 pt border,
    /// 8 pt corners) exposes its label text "Go". Card (320 × 200) contains
    /// `buttonsPerCard` Button instances, the first at (16, 140) with the label
    /// value "Buy" authored on it. The home page holds `cards` Card instances,
    /// the first at (40, 60).
    private func nestedButtonCardFixture(buttonsPerCard: Int = 1, buttonParts: Int = 0,
                                         cards: Int = 1) throws -> NestedButtonCardFixture {
        func geometry(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [NodeProperty] {
            [("layout.x", x), ("layout.y", y), ("layout.width", width), ("layout.height", height)].map {
                .init(key: .init(rawValue: $0.0), value: .number($0.1), origin: .authored)
            }
        }
        func reference(_ id: PageID) -> NodeProperty {
            .init(key: .init(rawValue: CanonicalComponentReference.key), value: .string(id.description))
        }
        var document = CanonicalDocument()
        let styleID = ReusableStyleID(), propertyID = ComponentTextPropertyID()
        let border = CanonicalBorder(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#336699FF")),
                                     width: 2, style: .solid)
        let prefix = CanonicalReusableStyleIndex.namespace + "definition.\(styleID.description)."
        document.pages[0].nodes[0].properties.append(.init(key: .init(rawValue: prefix + "name"),
            value: .string("Pill"), origin: .authored))
        document.pages[0].nodes[0].properties += CanonicalReusableBoxAppearance(border: border, cornerRadius: 8)
            .fieldValues.map { NodeProperty(key: .init(rawValue: prefix + $0.field), value: $0.value, origin: .authored) }

        let buttonID = PageID(), buttonRootID = NodeID(), labelID = NodeID()
        let label = DocumentNode(id: labelID, kind: .text, name: "Label", parent: .node(buttonRootID),
            properties: geometry(12, 8, 96, 24) + [
                .init(key: .init(rawValue: "content.text"), value: .string("Go")),
                .init(key: .init(rawValue: CanonicalComponentText.namespace + "id"),
                      value: .string(propertyID.description), origin: .authored),
                .init(key: .init(rawValue: CanonicalComponentText.namespace + "label"), value: .string("Label"), origin: .authored),
                .init(key: .init(rawValue: CanonicalComponentText.namespace + "type"), value: .string("plain-text"), origin: .authored),
            ])
        let parts = (0..<buttonParts).map { index in
            DocumentNode(kind: .frame, name: "Part \(index + 1)", parent: .node(buttonRootID),
                         properties: geometry(Double(index) * 4, 36, 4, 4))
        }
        let buttonRoot = DocumentNode(id: buttonRootID, kind: .frame, name: "Button", parent: .page(buttonID),
            childIDs: [labelID] + parts.map(\.id), properties: geometry(0, 0, 120, 40) + [
                .init(key: .init(rawValue: CanonicalReusableStyleIndex.appliedKey), value: .string(styleID.description),
                      origin: .authored)])
        document.pages.append(DocumentPage(id: buttonID, name: "Button", route: .init(rawValue: ""),
            role: .componentDefinition, provenance: .authored, rootNodeIDs: [buttonRootID],
            nodes: [buttonRoot, label] + parts))

        let cardID = PageID(), cardRootID = NodeID()
        let nested = (0..<buttonsPerCard).map { index in
            DocumentNode(kind: .component, name: "Button", parent: .node(cardRootID),
                properties: geometry(16 + Double(index % 2) * 140, 140 - Double(index / 2) * 60, 120, 40)
                    + [reference(buttonID)] + (index == 0 ? [.init(
                        key: .init(rawValue: CanonicalComponentText.overrideKey(propertyID)),
                        value: .string("Buy"), origin: .authored)] : []))
        }
        let cardRoot = DocumentNode(id: cardRootID, kind: .frame, name: "Card", parent: .page(cardID),
            childIDs: nested.map(\.id), properties: geometry(0, 0, 320, 200))
        document.pages.append(DocumentPage(id: cardID, name: "Card", route: .init(rawValue: ""),
            role: .componentDefinition, provenance: .authored, rootNodeIDs: [cardRootID], nodes: [cardRoot] + nested))

        let pageRootID = document.pages[0].rootNodeIDs[0]
        let instances = (0..<cards).map { index in
            DocumentNode(kind: .component, name: "Card", parent: .node(pageRootID),
                properties: geometry(40 + Double(index % 4) * 340, 60 + Double(index / 4) * 220, 320, 200)
                    + [reference(cardID)])
        }
        document.pages[0].nodes[0].childIDs += instances.map(\.id)
        document.pages[0].nodes += instances
        return .init(document: document, buttonID: buttonID, cardID: cardID, styleID: styleID, labelID: labelID,
                     nestedInstanceID: nested[0].id, cardInstanceID: instances[0].id)
    }

    // SF-0510-003, SF-0901-003: a component instance whose
    // definition root links a reusable style draws and exports the linked
    // border and corners; expansion keeps the definition's applied style IDs.
    func testComponentInstanceDrawsAndExportsItsDefinitionsLinkedBoxStyle() async throws {
        var document = CanonicalDocument()
        let rootID = document.pages[0].rootNodeIDs[0]
        let styleID = ReusableStyleID()
        let border = CanonicalBorder(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#336699FF")),
                                     width: 2, style: .solid)
        let box = CanonicalReusableBoxAppearance(border: border, cornerRadius: 8)
        let prefix = CanonicalReusableStyleIndex.namespace + "definition.\(styleID.description)."
        document.pages[0].nodes[0].properties.append(.init(key: .init(rawValue: prefix + "name"),
            value: .string("Card"), origin: .authored))
        document.pages[0].nodes[0].properties += box.fieldValues.map {
            NodeProperty(key: .init(rawValue: prefix + $0.field), value: $0.value, origin: .authored)
        }
        func geometry(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [NodeProperty] {
            [("layout.x", x), ("layout.y", y), ("layout.width", width), ("layout.height", height)].map {
                .init(key: .init(rawValue: $0.0), value: .number($0.1), origin: .authored)
            }
        }
        let definitionID = PageID(), definitionRootID = NodeID(), labelID = NodeID(), instanceID = NodeID()
        let definitionRoot = DocumentNode(id: definitionRootID, kind: .frame, name: "Root", parent: .page(definitionID),
            childIDs: [labelID], properties: geometry(0, 0, 240, 160) + [
                .init(key: .init(rawValue: CanonicalReusableStyleIndex.appliedKey), value: .string(styleID.description),
                      origin: .authored)])
        let label = DocumentNode(id: labelID, kind: .text, name: "Label", parent: .node(definitionRootID),
            properties: geometry(12, 12, 120, 24) + [.init(key: .init(rawValue: "content.text"), value: .string("Shared"))])
        let definition = DocumentPage(id: definitionID, name: "Card", route: .init(rawValue: ""), role: .componentDefinition,
            provenance: .authored, rootNodeIDs: [definitionRootID], nodes: [definitionRoot, label])
        let instance = DocumentNode(id: instanceID, kind: .component, name: "Card", parent: .node(rootID),
            properties: geometry(40, 60, 240, 160) + [
                .init(key: .init(rawValue: CanonicalComponentReference.key), value: .string(definitionID.description))])
        document.pages[0].nodes[0].childIDs.append(instanceID)
        document.pages[0].nodes.append(instance)
        document.pages.append(definition)
        try document.validate()

        let resolvedPage = try ComponentGraphResolver.resolvedPage(document.pages[0], in: document, breakpoint: .desktop)
        let expandedRoot = try XCTUnwrap(resolvedPage.nodes.first { $0.id == instanceID })
        XCTAssertEqual(expandedRoot.kind, .frame)
        XCTAssertEqual(CanonicalReusableStyleIndex.appliedIDs(expandedRoot), [styleID])
        let resolved = try XCTUnwrap(CanonicalLinkedBoxStyleResolver.resolve(node: expandedRoot, tokens: [],
            index: CanonicalReusableStyleIndex(document: document)))
        XCTAssertEqual(resolved.style.border, border)
        XCTAssertEqual(resolved.borderSource, .linked(styleID))

        let viewport = try CanvasViewportState(viewportSize: .init(width: 1200, height: 800),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1440, height: 900)), pixelRatio: .init(2))
        let prepared = try await WorkspaceScenePreparationWorker().prepare(.init(document: document,
            activePageID: document.pages[0].id, activeContainerID: nil, viewport: viewport, surfaceID: CanvasRenderSurfaceID()))
        let object = try XCTUnwrap(prepared.renderScene.objects.first { $0.id == instanceID })
        XCTAssertEqual(object.border?.width, 2)
        XCTAssertEqual(object.cornerRadius, 8)

        let plan = try MultiPageStaticBuildPlanner.plan(document: document)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        let selector = CanonicalCSSRule.selector(for: instanceID) + " { "
        let rules = css.split(separator: "\n").map(String.init).filter { $0.hasPrefix(selector) }.joined(separator: "\n")
        XCTAssertTrue(rules.contains("2.0px solid rgba(51.0, 102.0, 153.0, 1.0)"), css)
        XCTAssertTrue(rules.contains("border-radius: 8.0px;"), css)
    }

    // SF-0502-003 / SF-0503-003 / SF-0506-003 — one resolved structural
    // geometry map feeds immutable renderer, selection, hit testing, and AX.
    func testContainerLayoutProjectionSharesResolvedChildGeometryAcrossCanvasSystems() async throws {
        var document = ProjectCreation.blank()
        var page = try XCTUnwrap(document.pages.first)
        let rootID = try XCTUnwrap(page.rootNodeIDs.first)
        let rootIndex = try XCTUnwrap(page.nodes.firstIndex { $0.id == rootID })
        func geometry(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [NodeProperty] {
            [("layout.x", x), ("layout.y", y), ("layout.width", width), ("layout.height", height)].map {
                .init(key: .init(rawValue: $0.0), value: .number($0.1), origin: .authored)
            }
        }
        func structural(_ kind: NodeKind) -> [NodeProperty] {
            let values: [(String, PropertyValue)] = switch kind {
            case .section: [("layout.container.kind", .string("section")), ("layout.padding", .number(64)), ("layout.axis", .string("vertical"))]
            case .stack: [("layout.container.kind", .string("stack")), ("layout.axis", .string("horizontal")), ("layout.padding", .number(20)), ("layout.gap", .number(12)), ("layout.align", .string("center"))]
            case .grid: [("layout.container.kind", .string("grid")), ("layout.padding", .number(16)), ("layout.gap", .number(8)), ("layout.grid.columns", .number(2)), ("layout.grid.placement", .string("row-major"))]
            case .frame, .text, .image, .button, .link, .form, .component: []
            }
            return values.map { .init(key: .init(rawValue: $0.0), value: $0.1, origin: .authored) }
        }
        let sectionID = NodeID(), stackID = NodeID(), gridID = NodeID()
        let childIDs = (0..<6).map { _ in NodeID() }
        var section = DocumentNode(id: sectionID, kind: .section, name: "Section", parent: .node(rootID), properties: geometry(20, 20, 900, 360) + structural(.section))
        var stack = DocumentNode(id: stackID, kind: .stack, name: "Stack", parent: .node(rootID), properties: geometry(20, 420, 500, 180) + structural(.stack))
        var grid = DocumentNode(id: gridID, kind: .grid, name: "Grid", parent: .node(rootID), properties: geometry(540, 420, 420, 300) + structural(.grid))
        section.childIDs = [childIDs[0]]
        stack.childIDs = [childIDs[1], childIDs[2]]
        grid.childIDs = [childIDs[3], childIDs[4], childIDs[5]]
        let parents = [sectionID, stackID, stackID, gridID, gridID, gridID]
        let children = childIDs.enumerated().map { index, id in
            DocumentNode(id: id, kind: .frame, name: "Child \(index)", parent: .node(parents[index]),
                properties: geometry(900, 900, 80 + Double(index * 5), 40 + Double(index * 4)))
        }
        page.nodes[rootIndex].childIDs += [sectionID, stackID, gridID]
        page.nodes += [section, stack, grid] + children
        document.pages[0] = page
        XCTAssertNoThrow(try document.validate())
        let resolved = page.resolvedStructuralGeometry()
        let viewport = try CanvasViewportState(viewportSize: .init(width: 1_000, height: 800),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1_000, height: 800)), pixelRatio: .init(2))
        let prepared = try await WorkspaceScenePreparationWorker().prepare(.init(
            document: document, activePageID: page.id, activeContainerID: nil,
            viewport: viewport, surfaceID: CanvasRenderSurfaceID()
        ))
        let renderer = CanvasRendererCore()
        let plan = try renderer.prepare(scene: prepared.renderScene, overlays: prepared.overlays, viewport: viewport)
        for childID in childIDs {
            let expected = try XCTUnwrap(resolved[childID]?.frame)
            let object = try XCTUnwrap(plan.authoredObjects.first { $0.id == childID })
            let target = try XCTUnwrap(prepared.selectionScene?.targets.first { $0.id == childID })
            let accessibility = try XCTUnwrap(plan.accessibilityElements.first { $0.objectID == childID })
            XCTAssertEqual(object.frame, expected)
            XCTAssertEqual(target.frame, expected)
            XCTAssertEqual(accessibility.frame.origin, try viewport.transform.worldToViewport(expected.origin))
            XCTAssertEqual(renderer.hitTest(.init(x: expected.minX + 1, y: expected.minY + 1), in: plan), childID)
        }
        XCTAssertEqual(page.nodes.first { $0.id == gridID }?.childIDs, Array(childIDs[3...5]))
    }

    // SF-0601-003 / SF-0603-003 — responsive layout and visibility resolve
    // once before immutable renderer/selection/hit-test/AX projection.
    func testResponsiveContainerVisibilityExcludesHiddenChildAndReflowsSharedScene() async throws {
        var document = ProjectCreation.blank()
        var page = try XCTUnwrap(document.pages.first)
        let rootID = try XCTUnwrap(page.rootNodeIDs.first)
        let rootIndex = try XCTUnwrap(page.nodes.firstIndex { $0.id == rootID })
        func geometry(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [NodeProperty] {
            [("layout.x", x), ("layout.y", y), ("layout.width", width), ("layout.height", height)].map {
                .init(key: .init(rawValue: $0.0), value: .number($0.1), origin: .authored)
            }
        }
        let stackID = NodeID(), firstID = NodeID(), hiddenID = NodeID(), lastID = NodeID()
        var stack = DocumentNode(id: stackID, kind: .stack, name: "Responsive Stack", parent: .node(rootID),
            properties: geometry(20, 20, 500, 300) + [
                .init(key: .init(rawValue: "layout.container.kind"), value: .string("stack"), origin: .defaulted),
                .init(key: .init(rawValue: "layout.axis"), value: .string("vertical"), origin: .defaulted),
                .init(key: .init(rawValue: "layout.padding"), value: .number(24), origin: .defaulted),
                .init(key: .init(rawValue: "layout.gap"), value: .number(24), origin: .defaulted),
                .init(key: .init(rawValue: "layout.align"), value: .string("start"), origin: .defaulted),
                .init(key: .init(rawValue: ResponsiveContainerLayoutResolver.key(.axis, breakpoint: .mobile)),
                      value: .string("horizontal"), origin: .authored),
                .init(key: .init(rawValue: ResponsiveContainerLayoutResolver.key(.gap, breakpoint: .mobile)),
                      value: .number(10), origin: .authored),
            ])
        stack.childIDs = [firstID, hiddenID, lastID]
        let children = [firstID, hiddenID, lastID].enumerated().map { index, id in
            var properties = geometry(700, 700, 100, 80)
            if id == hiddenID {
                properties.append(.init(key: .init(rawValue: ResponsiveVisibilityResolver.key(.mobile)),
                                        value: .boolean(false), origin: .authored))
            }
            return DocumentNode(id: id, kind: .frame, name: "Child \(index)", parent: .node(stackID), properties: properties)
        }
        page.nodes[rootIndex].childIDs.append(stackID)
        page.nodes += [stack] + children
        document.pages[0] = page
        XCTAssertNoThrow(try document.validate())
        let resolved = page.resolvedStructuralGeometry(breakpoint: .mobile)
        let viewport = try CanvasViewportState(viewportSize: .init(width: 600, height: 500),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 390, height: 900)), pixelRatio: .init(2))
        let prepared = try await WorkspaceScenePreparationWorker().prepare(.init(
            document: document, activePageID: page.id, activeContainerID: nil,
            viewport: viewport, surfaceID: CanvasRenderSurfaceID(), breakpoint: .mobile
        ))
        XCTAssertNil(prepared.renderScene.objects.first { $0.id == hiddenID })
        let hiddenTarget = try XCTUnwrap(prepared.selectionScene?.targets.first { $0.id == hiddenID })
        XCTAssertFalse(hiddenTarget.isVisible)
        XCTAssertFalse(hiddenTarget.participatesInCanvasTraversal)
        XCTAssertNotNil(prepared.renderScene.objects.first { $0.id == firstID })
        XCTAssertNotNil(prepared.renderScene.objects.first { $0.id == lastID })
        XCTAssertEqual(resolved[firstID]?.origin.x, 44)
        XCTAssertEqual(resolved[lastID]?.origin.x, 154)
        let plan = try CanvasRendererCore().prepare(scene: prepared.renderScene, overlays: prepared.overlays, viewport: viewport)
        XCTAssertFalse(plan.authoredObjects.contains { $0.id == hiddenID })
        XCTAssertFalse(plan.accessibilityElements.contains { $0.objectID == hiddenID })
        XCTAssertNotEqual(CanvasRendererCore().hitTest(.init(x: 150, y: 80), in: plan), hiddenID)
    }

    // SF-0603-007 — the shared visibility cascade remains linear and bounded
    // for the specified standard and large fixtures.
    func testResponsiveVisibilityResolutionIsBoundedForStandardAndLargeFixtures() throws {
        for count in [100, 10_000] {
            var document = ProjectCreation.blank()
            var page = try XCTUnwrap(document.pages.first)
            let rootID = try XCTUnwrap(page.rootNodeIDs.first)
            let rootIndex = try XCTUnwrap(page.nodes.firstIndex { $0.id == rootID })
            let children = (0..<count).map { index -> DocumentNode in
                var properties = [
                    NodeProperty(key: .init(rawValue: "hidden"), value: .boolean(false), origin: .defaulted),
                    .init(key: .init(rawValue: "layout.x"), value: .number(Double(index)), origin: .authored),
                    .init(key: .init(rawValue: "layout.y"), value: .number(0), origin: .authored),
                    .init(key: .init(rawValue: "layout.width"), value: .number(10), origin: .authored),
                    .init(key: .init(rawValue: "layout.height"), value: .number(10), origin: .authored),
                ]
                if index.isMultiple(of: 10) {
                    properties.append(.init(
                        key: .init(rawValue: ResponsiveVisibilityResolver.key(.mobile)),
                        value: .boolean(false), origin: .authored
                    ))
                }
                return DocumentNode(
                    kind: .frame, name: "Object \(index)", parent: .node(rootID), properties: properties
                )
            }
            page.nodes[rootIndex].childIDs = children.map(\.id)
            page.nodes.append(contentsOf: children)
            let started = DispatchTime.now().uptimeNanoseconds
            let visible = page.effectiveVisibleNodeIDs(breakpoint: .mobile)
            let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            XCTAssertEqual(visible.count, 1 + count - (count / 10))
            XCTAssertLessThan(milliseconds, count == 100 ? 250 : 2_000)
        }
    }

    // SF-0407-006, SF-0407-007, SF-0407-008, SF-1502-001
    @MainActor
    func testProductionSceneProjectionAndRendererKeepMainActorResponsiveWhileWorkIsActive() async throws {
        let request = try makeWorkspacePreparationRequest(count: 10_000)
        let barrier = WorkspaceScenePreparationBarrier()
        let worker = WorkspaceScenePreparationWorker()
        let preparation = Task(priority: .userInitiated) {
            try await worker.prepare(
                request,
                progress: WorkspaceScenePreparationProgress { completed in
                    barrier.pauseOnce(at: completed)
                }
            )
        }

        // The real production projection is held at a deterministic progress
        // point. Reaching this assertion on MainActor while it is still active
        // proves the 10k traversal is not executing on MainActor itself.
        let didPause = await barrier.waitUntilPaused()
        XCTAssertTrue(didPause)
        XCTAssertTrue(barrier.isActivelyPaused)
        var heartbeatTurns = 0
        for _ in 0..<20 {
            heartbeatTurns += 1
            await Task.yield()
        }
        XCTAssertEqual(heartbeatTurns, 20)
        XCTAssertTrue(
            barrier.isActivelyPaused,
            "Production projection finished its held checkpoint before MainActor could make progress"
        )
        barrier.resume()

        let prepared = try await preparation.value
        let plan = try await CanvasRenderWorker().prepare(
            scene: prepared.renderScene,
            overlays: prepared.overlays,
            viewport: request.viewport
        )
        XCTAssertEqual(prepared.viewportRequest.objects.count, 10_000)
        XCTAssertEqual(prepared.selectionScene?.targets.count, 10_000)
        XCTAssertEqual(plan.authoredObjects.count, 10_000)
        XCTAssertEqual(plan.identity, prepared.renderScene.identity)
    }

    // SF-1201-001/003/004/005 — Preview adopts only an immutable authored
    // render plan and refresh never mutates the source plan or its overlays.
    func testLocalPreviewStateFreezesRevisionAndRejectsStaleRefreshes() throws {
        let fixture = try makeFixture(count: 2)
        let plan = try CanvasRendererCore().prepare(
            scene: fixture.scene, overlays: fixture.overlays, viewport: fixture.viewport
        )
        var preview = LocalPreviewState()
        preview.open(plan: plan)
        let first = try XCTUnwrap(preview.snapshot)
        XCTAssertEqual(first.documentID, plan.identity.documentID)
        XCTAssertEqual(first.revision, 7)
        XCTAssertEqual(first.objects, plan.authoredObjects)
        XCTAssertEqual(first.objects.first?.semanticElement, "article")
        preview.refresh(plan: plan)
        XCTAssertEqual(preview.snapshot, first)
        XCTAssertEqual(preview.status, "Preview already shows the current revision.")
        preview.open(plan: nil)
        XCTAssertNil(preview.snapshot)
        XCTAssertEqual(preview.status, "Preview unavailable until the current canvas is ready.")
        preview.close()
        XCTAssertNil(preview.snapshot)
        XCTAssertEqual(preview.status, "Preview closed")
    }

    // SF-1102-003/004/006, SF-1201-001/003/004/006 — Preview history and
    // routing are scene-local. Stable PageID targets navigate; missing and
    // external targets retain the current page and publish bounded recovery.
    func testLocalPreviewRuntimeNavigatesStableTargetsWithoutMutatingDocumentState() throws {
        let documentID = DocumentID(), homeID = PageID(), guideID = PageID(), sectionID = NodeID()
        let homeObject = CanvasRenderObject(
            id: NodeID(), frame: Self.frame, clipRect: Self.frame, paintOrder: 0,
            style: .textPlaceholder, isVisible: true, accessibilityLabel: "Guide",
            plainText: "Guide", previewLink: .init(target: .page(guideID), context: .same, isMissing: false)
        )
        let guideObject = CanvasRenderObject(
            id: sectionID, frame: Self.frame, clipRect: Self.frame, paintOrder: 0,
            style: .sectionSurface, isVisible: true, accessibilityLabel: "Details"
        )
        let runtime = LocalPreviewRuntimeSnapshot(
            documentID: documentID, revision: 9,
            pages: [
                .init(id: homeID, name: "Home", route: PageRoute(rawValue: "/"), role: .home,
                      viewportBounds: Self.frame, objects: [homeObject]),
                .init(id: guideID, name: "Guide", route: PageRoute(rawValue: "/guide"), role: .standard,
                      viewportBounds: Self.frame, objects: [guideObject]),
            ], deterministicDigest: "runtime"
        )
        var preview = LocalPreviewState()
        preview.adopt(runtime, initialPageID: homeID)
        XCTAssertEqual(preview.currentPageID, homeID)
        XCTAssertTrue(preview.follow(try XCTUnwrap(homeObject.previewLink)))
        XCTAssertEqual(preview.currentPageID, guideID)
        XCTAssertTrue(preview.canGoBack)
        preview.goBack()
        XCTAssertEqual(preview.currentPageID, homeID)
        preview.goForward()
        XCTAssertEqual(preview.currentPageID, guideID)

        let frozen = preview.snapshot
        XCTAssertFalse(preview.follow(.init(target: .page(PageID()), context: .same, isMissing: true)))
        XCTAssertEqual(preview.snapshot, frozen)
        XCTAssertTrue(preview.status.contains("missing"))
        XCTAssertFalse(preview.follow(.init(target: .external("https://example.com/private"), context: .new, isMissing: false)))
        XCTAssertEqual(preview.snapshot, frozen)
        XCTAssertFalse(preview.status.contains("/private"), "Preview status must not echo authored external paths")
        preview.rejectRuntimePreparation()
        XCTAssertEqual(preview.snapshot, frozen)
        XCTAssertTrue(preview.status.contains("last valid page remains visible"))
    }

    func testScenePreparationCarriesOnlyValidatedLinkNavigationIntoPreview() async throws {
        var document = ProjectCreation.blank()
        let pageID = try XCTUnwrap(document.pages.first?.id)
        let targetID = PageID()
        let target = DocumentPage(id: targetID, name: "Guide", route: PageRoute(rawValue: "/guide"), role: .standard,
                                  provenance: .authored, rootNodeIDs: [], nodes: [])
        let linkID = NodeID()
        var page = try XCTUnwrap(document.pages.first)
        page.rootNodeIDs.append(linkID)
        page.nodes.append(.init(
            id: linkID, kind: .link, name: "Guide", parent: .page(pageID),
            properties: [
                .init(key: .init(rawValue: "layout.x"), value: .number(20)),
                .init(key: .init(rawValue: "layout.y"), value: .number(20)),
                .init(key: .init(rawValue: "layout.width"), value: .number(120)),
                .init(key: .init(rawValue: "layout.height"), value: .number(24)),
            ] + typedControlProperties(.page(targetID), label: "Guide")
        ))
        document.pages[0] = page
        document.pages.append(target)
        let viewport = try CanvasViewportState()
        let result = try await WorkspaceScenePreparationWorker().prepare(.init(
            document: document, activePageID: pageID, activeContainerID: nil,
            viewport: viewport, surfaceID: CanvasRenderSurfaceID()
        ))
        XCTAssertEqual(result.renderScene.objects.first(where: { $0.id == linkID })?.previewLink,
                       .init(target: .page(targetID), context: .same, isMissing: false))
    }

    func testPreviewNavigationScalesLayoutAndHitBoundsInsideAuthoredOwner() throws {
        let frame = WorldRect(origin: .init(x: 40, y: 120), size: .init(width: 1440, height: 120))
        for scale in [0.25, 0.35, 1, 2, 8] {
            let geometry = try XCTUnwrap(CanvasPreviewNavigationGeometry(frame: frame, padding: 48, rowHeight: 24, scale: scale))
            XCTAssertEqual(geometry.worldSize, .init(width: 1344, height: 24))
            XCTAssertEqual(geometry.displaySize.width, 1344 * scale, accuracy: 0.000_001)
            XCTAssertEqual(geometry.displayOrigin.x, 48 * scale, accuracy: 0.000_001)
            XCTAssertLessThanOrEqual(geometry.displayOrigin.x + geometry.displaySize.width, frame.size.width * scale)
            XCTAssertLessThanOrEqual(geometry.displayOrigin.y + geometry.displaySize.height, frame.size.height * scale)
        }
        XCTAssertNil(CanvasPreviewNavigationGeometry(frame: frame, padding: 80, rowHeight: 24, scale: 1))
        XCTAssertNil(CanvasPreviewNavigationGeometry(frame: frame, padding: 48, rowHeight: 24, scale: .nan))
        XCTAssertNil(CanvasPreviewNavigationGeometry(frame: frame, padding: 48, rowHeight: 24, scale: 0))
        XCTAssertEqual(frame.origin, .init(x: 40, y: 120))
    }

    // SF-0701-006, SF-1202-003: full-height fitting must not turn an
    // interactive phone page into a tiny, unhittable native-control thumbnail.
    func testNativePreviewFitsWidthAndScrollsTallPagesWithoutChangingAuthoredBounds() throws {
        for width in [320.0, 430, 768, 1440] {
            let bounds = WorldRect(origin: .init(x: 0, y: 0), size: .init(width: width, height: 900))
            for height in [200.0, 329, 700] {
                let layout = try XCTUnwrap(CanvasPreviewPresentationGeometry(bounds: bounds,
                    available: .init(width: 620, height: height)))
                XCTAssertEqual(layout.scale, min(1, 564 / width))
                XCTAssertEqual(layout.contentSize.width, 620)
                XCTAssertGreaterThanOrEqual(layout.contentSize.height, height)
                XCTAssertEqual(layout.contentSize.height, max(height, 900 * layout.scale + 56))
                if width <= 430 { XCTAssertEqual(layout.scale, 1) }
                XCTAssertEqual(bounds.size, .init(width: width, height: 900))
            }
        }
        XCTAssertNil(CanvasPreviewPresentationGeometry(bounds: Self.frame, available: .init(width: .nan, height: 329)))
        XCTAssertNil(CanvasPreviewPresentationGeometry(bounds: Self.frame, available: .init(width: 620, height: 0)))
    }

    // SF-0701-006, SF-1202-003: native visitor navigation owns its own
    // label and pointer surface; canvas-only proxy glyphs cannot cover it.
    func testNativePreviewDecorationsDoNotOwnAccessibilityOverRealContent() {
        let frame = Self.frame
        let surface = CanvasRenderObject(id: NodeID(), frame: frame, clipRect: frame,
            paintOrder: 0, style: .sectionSurface, isVisible: true, accessibilityLabel: "Header")
        let page = PageID()
        let navigation = PageNavigationSnapshot(ownerID: NodeID(), links: [
            .init(id: NodeID(), pageID: page, label: "Home", isAvailable: true)],
            hamburgerEnabled: true, usesHamburger: true, alignment: "start", padding: 0)
        let menu = CanvasRenderObject(id: navigation.ownerID, frame: frame, clipRect: frame,
            paintOrder: 1, style: .textPlaceholder, isVisible: true, accessibilityLabel: "Navigation",
            navigation: navigation)
        let text = CanvasRenderObject(id: NodeID(), frame: frame, clipRect: nil,
            paintOrder: 2, style: .textPlaceholder, isVisible: true, accessibilityLabel: "Title", plainText: "Title")
        let image = CanvasRenderObject(id: NodeID(), frame: frame, clipRect: nil,
            paintOrder: 3, style: .imagePlaceholder, isVisible: true, accessibilityLabel: "Image", imageAssetID: AssetID())
        let link = CanvasRenderObject(id: NodeID(), frame: frame, clipRect: nil,
            paintOrder: 4, style: .frameSurface, isVisible: true, accessibilityLabel: "Home",
            previewLink: .init(target: .page(page), context: .same, isMissing: false))
        XCTAssertTrue(surface.isNativePreviewDecoration)
        for object in [menu, text, image, link] {
            XCTAssertFalse(object.isNativePreviewDecoration, "Real readable or actionable content retains AX semantics")
            XCTAssertEqual(object.frame, frame)
        }
        XCTAssertEqual(menu.id, navigation.ownerID)
        XCTAssertEqual(surface.clipRect, frame)
        XCTAssertEqual(surface.frame, frame, "AX policy must not change paint, clipping, or canonical geometry")
    }

    func testNativePreviewPageChromeGroupsUseCanonicalAncestryWithoutMovingFrames() throws {
        let headerID = NodeID(), contentID = NodeID(), navigationID = NodeID(), independentID = NodeID()
        let header = CanvasRenderObject(id: headerID, frame: Self.frame, clipRect: nil,
            paintOrder: 0, style: .sectionSurface, isVisible: true, accessibilityLabel: "Header", pageFlowRole: .header)
        let content = CanvasRenderObject(id: contentID, frame: Self.frame, clipRect: Self.frame,
            paintOrder: 1, style: .stackSurface, isVisible: true, accessibilityLabel: "Content", parentNodeID: headerID)
        let page = PageID()
        let navigation = PageNavigationSnapshot(ownerID: navigationID, links: [
            .init(id: NodeID(), pageID: page, label: "Home", isAvailable: true)],
            hamburgerEnabled: true, usesHamburger: true, alignment: "start", padding: 0)
        let control = CanvasRenderObject(id: navigationID, frame: Self.frame, clipRect: Self.frame,
            paintOrder: 2, style: .textPlaceholder, isVisible: true, accessibilityLabel: "Navigation",
            navigation: navigation, parentNodeID: contentID)
        let independent = CanvasRenderObject(id: independentID, frame: Self.frame, clipRect: nil,
            paintOrder: 3, style: .frameSurface, isVisible: true, accessibilityLabel: "Unrelated")
        let source = [independent, control, header, content]
        let groups = CanvasPreviewPresentationGroup.resolve(source)
        XCTAssertEqual(groups.map(\.id), [headerID, independentID])
        XCTAssertEqual(groups[0].container, header)
        XCTAssertEqual(groups[0].objects, [header, content, control])
        XCTAssertNil(groups[1].container, "Rectangle overlap must never invent canonical ancestry")
        XCTAssertEqual(groups[1].objects, [independent])
        let reopened = try JSONDecoder().decode([CanvasRenderObject].self, from: JSONEncoder().encode(source))
        XCTAssertEqual(CanvasPreviewPresentationGroup.resolve(reopened), groups)
        XCTAssertEqual(reopened, source, "Grouping must preserve exact world geometry, IDs, clipping and properties")
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(header)) as? [String: Any])
        old.removeValue(forKey: "parentNodeID"); old.removeValue(forKey: "pageFlowRole")
        let legacy = try JSONDecoder().decode(CanvasRenderObject.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(legacy.parentNodeID); XCTAssertNil(legacy.pageFlowRole)
        XCTAssertEqual(legacy.frame, header.frame)
    }

    func testNativePreviewNavigationReplacesCanvasProxyTextButPreservesOrdinaryText() {
        let owner = NodeID()
        let navigation = PageNavigationSnapshot(ownerID: owner,
            links: [.init(id: NodeID(), pageID: PageID(), label: "About", isAvailable: true)], hamburgerEnabled: true,
            usesHamburger: true, alignment: "start", padding: 0)
        let menu = CanvasRenderObject(id: owner, frame: Self.frame, clipRect: nil, paintOrder: 0,
            style: .textPlaceholder, isVisible: true, accessibilityLabel: "Navigation",
            plainText: "☰ Menu", navigation: navigation)
        XCTAssertFalse(menu.paintsStandalonePreviewText)
        XCTAssertEqual(menu.plainText, "☰ Menu", "The editor raster proxy is retained, not rewritten")
        XCTAssertEqual(menu.navigation, navigation)
        let text = CanvasRenderObject(id: NodeID(), frame: Self.frame, clipRect: nil, paintOrder: 1,
            style: .textPlaceholder, isVisible: true, accessibilityLabel: "Text object", plainText: "Menu")
        XCTAssertTrue(text.paintsStandalonePreviewText, "An ordinary authored word is not mistaken for navigation")
        let empty = CanvasRenderObject(id: NodeID(), frame: Self.frame, clipRect: nil, paintOrder: 2,
            style: .frameSurface, isVisible: true, accessibilityLabel: "Frame")
        XCTAssertFalse(empty.paintsStandalonePreviewText)
    }

    // SF-1006-001/003/004/008 — Inspector-facing local validation adopts only
    // a current identity-tagged category snapshot; it retains no visitor value
    // and self-invalidates on a later canonical revision.
    func testLocalFormValidationPreviewStateAdoptsOnlyCurrentCategorySnapshot() {
        let documentID = DocumentID()
        let formID = NodeID()
        let fieldID = NodeID()
        let identity = FormValidationResultIdentity(documentID: documentID, revision: 7, formID: formID, fieldID: fieldID)
        let result = FormValidationSnapshot(
            identity: .init(documentID: documentID, revision: 7, formID: formID, fieldID: nil),
            fields: [.init(identity: identity, failures: [.required])], staticOutputCompatibility: .unavailableSubmission
        )
        var state = LocalFormValidationPreviewState()
        state.adopt(result, expectedDocumentID: documentID, revision: 7, formID: formID)
        XCTAssertEqual(state.snapshot, result)
        XCTAssertFalse(state.status.contains("visitor-secret"))

        var document = ProjectCreation.blank()
        document.revision = 8
        state.invalidate(for: document)
        XCTAssertNil(state.snapshot)
        XCTAssertEqual(state.status, "Local validation is stale. Review the live form and validate again.")
    }

    // SF-1006-006/008 — accessibility surfaces receive only the local
    // category/count summary; entered visitor values cannot leak through it.
    func testLocalFormValidationAccessibilitySummaryIsRedactedAndSceneLocal() {
        let documentID = DocumentID(), formID = NodeID(), fieldID = NodeID()
        let result = FormValidationSnapshot(
            identity: .init(documentID: documentID, revision: 3, formID: formID, fieldID: nil),
            fields: [.init(identity: .init(documentID: documentID, revision: 3, formID: formID, fieldID: fieldID), failures: [.invalidEmail])],
            staticOutputCompatibility: .unavailableSubmission
        )
        var state = LocalFormValidationPreviewState()
        state.adopt(result, expectedDocumentID: documentID, revision: 3, formID: formID)
        let summary = LocalFormValidationAccessibilitySummary(state: state)
        XCTAssertEqual(summary.label, "Local form validation")
        XCTAssertTrue(summary.value.contains("1 field issue"))
        XCTAssertFalse(summary.value.contains(fieldID.description))
        XCTAssertEqual(summary.hint, "Validate the selected Form locally. Submission is unavailable.")
    }

    private struct Fixture {
        let scene: CanvasRenderSceneSnapshot
        let overlays: CanvasEditorOverlaySnapshot
        let viewport: CanvasViewportState
    }

    private func makeFixture(count: Int, overlapping: Bool = false) throws -> Fixture {
        let documentID = DocumentID(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        let sceneID = CanvasViewportSceneID(UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
        let identity = CanvasRenderRequestIdentity(
            documentID: documentID,
            revision: 7,
            sceneID: sceneID,
            sceneGeneration: 9,
            viewportGeneration: 11,
            scale: try CanvasPixelRatio(2)
        )
        let objects = (0..<count).map { index in
            CanvasRenderObject(
                id: NodeID(deterministicUUID(index)),
                frame: WorldRect(
                    origin: overlapping
                        ? WorldPoint(x: 50, y: 50)
                        : WorldPoint(x: Double((index % 100) * 12), y: Double((index / 100) * 12)),
                    size: WorldSize(width: 10, height: 10)
                ),
                clipRect: WorldRect(origin: WorldPoint(x: 0, y: 0), size: WorldSize(width: 1_440, height: 1_400)),
                paintOrder: index,
                style: index.isMultiple(of: 2) ? .container : .page,
                isVisible: true,
                accessibilityLabel: "Object \(index + 1)",
                semanticElement: index == 0 ? "article" : "p"
            )
        }
        let viewport = try CanvasViewportState(
            worldOrigin: WorldPoint(x: 0, y: 0),
            viewportSize: ViewportSize(width: 1_000, height: 700),
            contentBounds: WorldRect(origin: WorldPoint(x: 0, y: 0), size: WorldSize(width: 1_440, height: 1_400)),
            pixelRatio: CanvasPixelRatio(2)
        )
        let scene = CanvasRenderSceneSnapshot(
            identity: identity,
            surfaceID: CanvasRenderSurfaceID(UUID(uuidString: "33333333-3333-3333-3333-333333333333")!),
            objects: objects
        )
        return Fixture(scene: scene, overlays: CanvasEditorOverlaySnapshot(identity: identity, overlays: []), viewport: viewport)
    }

    // SF-0409-003/007 — one immutable preparation projects only the canonical
    // isolated subtree; unrelated authored siblings cannot leak into render,
    // hit-test, Layers, or accessibility snapshots.
    func testWorkspacePreparationProjectsOnlyIsolatedCanonicalSubtree() async throws {
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id
        let ownerID = document.pages[0].rootNodeIDs[0]
        let isolatedID = NodeID(), childID = NodeID(), siblingID = NodeID()
        func frame(_ id: NodeID, _ name: String, _ parent: NodeParent, _ children: [NodeID], _ x: Double) -> DocumentNode {
            .init(id: id, kind: .frame, name: name, parent: parent, childIDs: children, properties: [
                .init(key: .init(rawValue: "layout.x"), value: .number(x)),
                .init(key: .init(rawValue: "layout.y"), value: .number(40)),
                .init(key: .init(rawValue: "layout.width"), value: .number(160)),
                .init(key: .init(rawValue: "layout.height"), value: .number(120))
            ])
        }
        document.pages[0].nodes[0].childIDs = [isolatedID, siblingID]
        document.pages[0].nodes.append(frame(isolatedID, "Isolated", .node(ownerID), [childID], 40))
        document.pages[0].nodes.append(frame(childID, "Child", .node(isolatedID), [], 60))
        document.pages[0].nodes.append(frame(siblingID, "Sibling", .node(ownerID), [], 420))
        try document.validate()
        let viewport = try CanvasViewportState(viewportSize: .init(width: 900, height: 700),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1_440, height: 1_000)))
        let result = try await WorkspaceScenePreparationWorker().prepare(.init(
            document: document, activePageID: pageID, activeContainerID: isolatedID,
            isolationRootID: isolatedID, viewport: viewport, surfaceID: CanvasRenderSurfaceID()))
        XCTAssertEqual(Set(result.renderScene.objects.map(\.id)), [isolatedID, childID])
        XCTAssertEqual(Set(result.selectionScene?.targets.map(\.id) ?? []), [isolatedID, childID])
        XCTAssertFalse(result.renderScene.objects.contains { $0.id == siblingID })
    }

    private func makeWorkspacePreparationRequest(count: Int) throws -> WorkspaceScenePreparationRequest {
        precondition(count > 0)
        let documentID = DocumentID(UUID(uuidString: "55555555-1111-4111-8111-111111111111")!)
        let pageID = PageID(UUID(uuidString: "55555555-2222-4222-8222-222222222222")!)
        let ids = (0..<count).map { NodeID(deterministicUUID(20_000 + $0)) }
        let rootID = ids[0]
        func geometry(_ index: Int) -> [NodeProperty] {
            [
                .init(key: .init(rawValue: "layout.x"), value: .number(Double((index % 100) * 12))),
                .init(key: .init(rawValue: "layout.y"), value: .number(Double((index / 100) * 12))),
                .init(key: .init(rawValue: "layout.width"), value: .number(10)),
                .init(key: .init(rawValue: "layout.height"), value: .number(10)),
            ]
        }
        let nodes = ids.enumerated().map { index, id in
            DocumentNode(
                id: id,
                kind: .frame,
                name: index == 0 ? "Root" : "Frame \(index)",
                parent: index == 0 ? .page(pageID) : .node(rootID),
                childIDs: index == 0 ? Array(ids.dropFirst()) : [],
                properties: geometry(index)
            )
        }
        let document = CanonicalDocument(
            id: documentID,
            revision: 17,
            pages: [DocumentPage(
                id: pageID,
                name: "Performance",
                route: .init(rawValue: "/performance"),
                role: .home,
                rootNodeIDs: [rootID],
                nodes: nodes
            )]
        )
        let viewport = try CanvasViewportState(
            worldOrigin: .init(x: 0, y: 0),
            viewportSize: .init(width: 1_000, height: 700),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1_440, height: 1_400)),
            pixelRatio: .init(2)
        )
        return WorkspaceScenePreparationRequest(
            document: document,
            activePageID: pageID,
            activeContainerID: rootID,
            viewport: viewport,
            surfaceID: CanvasRenderSurfaceID(UUID(uuidString: "55555555-3333-4333-8333-333333333333")!)
        )
    }

    private func deterministicUUID(_ value: Int) -> UUID {
        let suffix = String(format: "%012x", value + 1)
        return UUID(uuidString: "44444444-4444-4444-8444-\(suffix)")!
    }

    private func fillLayer(_ identifier: String, rgba: [Double]) -> CanvasAuthoredFillLayer {
        CanvasAuthoredFillLayer(
            id: UUID(uuidString: identifier)!, kind: .solid,
            isEnabled: true, rgba: rgba, angleDegrees: nil, stops: []
        )
    }

    private func gradientLayer(_ identifier: String, angle: Double, stops: [CanvasGradientStop]) -> CanvasAuthoredFillLayer {
        CanvasAuthoredFillLayer(
            id: UUID(uuidString: identifier)!, kind: .linearGradient,
            isEnabled: true, rgba: nil, angleDegrees: angle, stops: stops
        )
    }

    private func gradientStop(_ identifier: String, position: Double, rgba: [Double]) -> CanvasGradientStop {
        CanvasGradientStop(id: UUID(uuidString: identifier)!, position: position, rgba: rgba)
    }

    private func assertRGBA(
        _ actual: [Double],
        equals expected: [Double],
        accuracy: Double = 0.000_001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actualChannel, expectedChannel) in zip(actual, expected) {
            XCTAssertEqual(actualChannel, expectedChannel, accuracy: accuracy, file: file, line: line)
        }
    }
}

private final class WorkspaceScenePreparationBarrier: @unchecked Sendable {
    private let lock = NSLock()
    private let release = DispatchSemaphore(value: 0)
    private var didPause = false
    private var pauseIsActive = false
    private var pauseWaiter: CheckedContinuation<Bool, Never>?

    func pauseOnce(at completed: Int) {
        guard completed >= 64 else { return }
        lock.lock()
        let shouldPause = !didPause
        didPause = true
        pauseIsActive = shouldPause
        let waiter = pauseWaiter
        pauseWaiter = nil
        lock.unlock()
        guard shouldPause else { return }
        waiter?.resume(returning: true)
        _ = release.wait(timeout: .now() + 10)
        lock.lock()
        pauseIsActive = false
        lock.unlock()
    }

    func waitUntilPaused() async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            if didPause {
                lock.unlock()
                continuation.resume(returning: true)
            } else {
                pauseWaiter = continuation
                lock.unlock()
            }
        }
    }

    func resume() {
        release.signal()
    }

    var isActivelyPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pauseIsActive
    }
}
