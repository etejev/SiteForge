import CryptoKit
import Combine
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SiteForge

final class ProjectResourceTests: XCTestCase {

    // SF-0807-001/002/003/004/005: every use of an asset is listed (Image,
    // component default, component value, favicon); Use Another Asset Instead
    // moves all of them to another asset in one undoable step, keeping each
    // use's other settings; the original becomes unused and Remove Unused
    // removes only unused assets, also in one undoable step.
    @MainActor
    func testAssetUsesRetargetToAnotherAssetAndUnusedAssetsAreRemovedInOneStep() throws {
        func asset(_ name: String, _ bytes: [UInt8]) -> ImageAsset {
            .init(id: AssetID(), resourceID: ResourceID(), displayName: name, originalFilename: name.lowercased() + ".png",
                  format: .png, pixelWidth: 4, pixelHeight: 4, byteCount: bytes.count, contentHash: ProjectResourceStore.digest(Data(bytes)))
        }
        let hero = asset("Hero", [1, 2, 3]), banner = asset("Banner", [4, 5, 6]), spare = asset("Spare", [7, 8, 9])
        var document = ProjectCreation.blank()
        document.imageAssets = [hero, banner, spare]
        let root = document.pages[0].rootNodeIDs[0]
        func image(_ alt: String) -> DocumentNode {
            DocumentNode(kind: .image, name: "Image", parent: .node(root), properties: [
                ("layout.x", PropertyValue.number(0)), ("layout.y", .number(0)), ("layout.width", .number(100)), ("layout.height", .number(80)),
                (CanonicalImageStyle.namespace + "assetID", .string(hero.id.description)),
                (CanonicalImageStyle.namespace + "fit", .string(ImageFitMode.fill.rawValue)),
                (CanonicalImageStyle.namespace + "focal.x", .number(0.25)), (CanonicalImageStyle.namespace + "focal.y", .number(0.5)),
                (CanonicalImageStyle.namespace + "alt", .string(alt)), (CanonicalImageStyle.namespace + "decorative", .boolean(false)),
            ].map { NodeProperty(key: .init(rawValue: $0.0), value: $0.1) })
        }
        let first = image("A hero"), second = image("Another hero")
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == root })
        document.pages[0].nodes[rootIndex].childIDs += [first.id, second.id]
        document.pages[0].nodes += [first, second]
        document.websiteMetadata = WebsiteMetadata(siteName: "Site", faviconAssetID: hero.id)
        try document.validate()

        let uses = ImageAssetReference.references(to: hero.id, in: document)
        XCTAssertEqual(uses.map(\.kind), [.image, .image, .favicon])
        XCTAssertEqual(Set(uses.compactMap(\.nodeID)), [first.id, second.id])
        XCTAssertEqual(ImageAssetDependencies.unusedAssetIDs(in: document), [banner.id, spare.id])

        let session = DocumentSession(document: document)
        let retarget = try ImageAssetDependencies.retarget(from: hero.id, to: banner.id, in: session.document,
            expectedRevision: session.document.revision, isLifecycleAvailable: true)
        XCTAssertEqual(retarget.count, 3)
        try session.execute(retarget.command)
        XCTAssertTrue(ImageAssetReference.references(to: hero.id, in: session.document).isEmpty)
        XCTAssertEqual(ImageAssetReference.references(to: banner.id, in: session.document).count, 3)
        XCTAssertEqual(session.document.websiteMetadata?.faviconAssetID, banner.id)
        let moved = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == first.id })
        XCTAssertEqual(moved.insertionStringProperty(CanonicalImageStyle.namespace + "alt"), "A hero", "Other settings are kept")
        XCTAssertEqual(moved.insertionNumberProperty(CanonicalImageStyle.namespace + "focal.x"), 0.25)
        XCTAssertEqual(moved.insertionProperty(CanonicalImageStyle.namespace + "assetID")?.id,
                       first.insertionProperty(CanonicalImageStyle.namespace + "assetID")?.id, "Same property identity")
        XCTAssertTrue(session.document.imageAssets.contains { $0.id == hero.id }, "The original asset is kept")
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)

        for (label, source, target, revision, reason) in [
            ("same asset", banner.id, banner.id, session.document.revision, "different asset"),
            ("unused source", hero.id, banner.id, session.document.revision, "Nothing uses"),
            ("missing target", banner.id, AssetID(), session.document.revision, "no longer exists"),
            ("stale", banner.id, spare.id, session.document.revision - 1, "changed"),
        ] {
            XCTAssertThrowsError(try ImageAssetDependencies.retarget(from: source, to: target, in: session.document,
                expectedRevision: revision, isLifecycleAvailable: true), label) {
                XCTAssertTrue($0.localizedDescription.contains(reason), "\(label): \($0.localizedDescription)")
            }
        }

        let cleanup = try ImageAssetDependencies.removeUnused(in: session.document, expectedRevision: session.document.revision,
                                                              isLifecycleAvailable: true)
        XCTAssertEqual(cleanup.count, 2)
        try session.execute(cleanup.command)
        XCTAssertEqual(session.document.imageAssets.map(\.id), [banner.id], "Only the asset in use remains")
        XCTAssertThrowsError(try ImageAssetDependencies.removeUnused(in: session.document, expectedRevision: session.document.revision,
                                                                     isLifecycleAvailable: true)) {
            XCTAssertTrue($0.localizedDescription.contains("Every asset is in use"))
        }
        try session.undo(); try session.undo()
        XCTAssertEqual(session.document.pages, document.pages)
        XCTAssertEqual(session.document.imageAssets, document.imageAssets)
        XCTAssertEqual(session.document.websiteMetadata, document.websiteMetadata)
        XCTAssertThrowsError(try ImageAssetDependencies.removeUnused(in: session.document, expectedRevision: session.document.revision,
                                                                     isLifecycleAvailable: false)) {
            XCTAssertTrue($0.localizedDescription.contains("busy"))
        }
    }

    // SF-0807-002/004/005/007 (OD-035, ADR-0144): Use Another Asset Instead
    // also moves collection item images, in the same undoable step, so the
    // source really becomes unused; the one-pass used set agrees with the
    // per-asset scans (pages, favicon, social image, collection items).
    @MainActor
    func testAssetRetargetMovesCollectionItemImagesAndUsedSetMatchesPerAssetScans() throws {
        func asset(_ name: String, _ byte: UInt8) -> ImageAsset {
            .init(resourceID: ResourceID(), displayName: name, originalFilename: name.lowercased() + ".png", format: .png,
                  pixelWidth: 4, pixelHeight: 4, byteCount: 1, contentHash: ProjectResourceStore.digest(Data([byte])))
        }
        let hero = asset("Hero", 1), banner = asset("Banner", 2), share = asset("Share", 3), spare = asset("Spare", 4)
        var document = ProjectCreation.blank()
        document.imageAssets = [hero, banner, share, spare]
        let cover = CollectionField(key: "cover", label: "Cover", type: .image)
        document.collections = [ContentCollection(name: "Posts", slug: "posts", fields: [cover],
            items: [CollectionItem(slug: "first", values: [.init(fieldID: cover.id, value: .image(hero.id))])])]
        document.websiteMetadata = WebsiteMetadata(siteName: "Site", socialImageAssetID: share.id)
        try document.validate()

        XCTAssertEqual(ImageAssetDependencies.usedAssetIDs(in: document), [hero.id, share.id])
        XCTAssertEqual(ImageAssetDependencies.unusedAssetIDs(in: document), [banner.id, spare.id])
        for candidate in document.imageAssets {
            let scanned = !ImageAssetReference.references(to: candidate.id, in: document).isEmpty
                || CanonicalCollections.usesAsset(candidate.id, in: document.collections)
                || CanonicalTranslations.usesAsset(candidate.id, in: document)
            XCTAssertEqual(ImageAssetDependencies.usedAssetIDs(in: document).contains(candidate.id), scanned, candidate.displayName)
        }

        let session = DocumentSession(document: document)
        let moved = try ImageAssetDependencies.retarget(from: hero.id, to: banner.id, in: session.document,
            expectedRevision: session.document.revision, isLifecycleAvailable: true)
        XCTAssertEqual(moved.count, 1, "The collection item's image")
        try session.execute(moved.command)
        XCTAssertEqual(session.document.collections[0].items[0].value(for: cover.id), .image(banner.id))
        XCTAssertEqual(ImageAssetDependencies.unusedAssetIDs(in: session.document), [hero.id, spare.id], "The source is now unused")
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        let social = try ImageAssetDependencies.retarget(from: share.id, to: spare.id, in: session.document,
            expectedRevision: session.document.revision, isLifecycleAvailable: true)
        XCTAssertEqual(social.count, 1)
        try session.execute(social.command)
        XCTAssertEqual(session.document.websiteMetadata?.socialImageAssetID, spare.id)
        try session.undo(); try session.undo()
        XCTAssertEqual(session.document.collections, document.collections)
        XCTAssertEqual(session.document.websiteMetadata, document.websiteMetadata)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    // SF-0802-003/004/008: inspect the real generated pixels and decode them.
    func testGeneratedQRCodeQuietZoneSharpPixelsAndActualPayload() async throws {
        let result = try await QRCodeResourceWorker().prepare(payload: "https://example.com")
        try ProjectQRCodeVerifier.verify(result.data, payload: "https://example.com")
        XCTAssertThrowsError(try ProjectQRCodeVerifier.verify(result.data, payload: "https://example.com/wrong"))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(result.data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, image.height); XCTAssertEqual(image.width % 8, 0)
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var black = 0
        for y in 0..<image.height { for x in 0..<image.width {
            let offset = (y * image.width + x) * 4
            XCTAssertTrue(bytes[offset] == 0 || bytes[offset] == 255, "QR pixels must stay sharp without interpolation")
            if x < 32 || y < 32 || x >= image.width - 32 || y >= image.height - 32 {
                XCTAssertEqual(bytes[offset], 255); XCTAssertEqual(bytes[offset+1], 255); XCTAssertEqual(bytes[offset+2], 255)
            }
            if bytes[offset] == 0 { black += 1 }
            XCTAssertEqual(bytes[offset+3], 255)
        } }
        XCTAssertGreaterThan(black, image.width)
        let attachment = XCTAttachment(data: result.data, uniformTypeIdentifier: "public.png")
        attachment.name = "Locally generated and decoded QR with quiet zone"; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testPackageBackedOutputWorkersPreserveImageBytesAndCanonicalIdentity() async throws {
        let (session, asset, bytes, _) = try twoImageUseFixture(), fixture = try makeFixture()
        let lifecycle = DocumentLifecycleController(session: session, recoveryDirectory: fixture.url.appendingPathComponent("recovery"))
        let descriptor = ProjectResourceDescriptor(id: asset.resourceID, filename: asset.originalFilename, mediaType: "image/png",
            byteCount: bytes.count, sha256: asset.contentHash)
        _ = try lifecycle.installingProjectResource(descriptor, data: bytes) {
            try session.execute(.renamePage(.init(pageID: session.document.pages[0].id, name: "Output snapshot")))
        }
        let document = session.document, package = lifecycle.staticBuildResourceSnapshot()
        let worker = StaticBuildWorker()
        let compiled = await worker.compile(document: document, profile: .init(profile: .development), package: package)
        XCTAssertTrue(compiled.canWrite, compiled.redactedSummary)
        XCTAssertTrue(try XCTUnwrap(compiled.plan).binaryFiles.contains { $0.contents == bytes })
        let snapshot = try ProjectImageResourceSnapshot(document: document, package: package)
        XCTAssertEqual(snapshot.images[asset.id], bytes)
        XCTAssertEqual(snapshot.descriptors[asset.resourceID], descriptor)
        XCTAssertEqual(compiled.documentID, document.id); XCTAssertEqual(compiled.revision, document.revision)
        XCTAssertEqual(session.document, document)
    }

    @MainActor func testNativePreviewRefreshAndStaticWriteRespectInvalidDraftBoundary() async throws {
        let (session, _, _, ids) = try twoImageUseFixture(), fixture = try makeFixture()
        let lifecycle = DocumentLifecycleController(session: session, recoveryDirectory: fixture.url.appendingPathComponent("recovery"))
        let state = WorkspaceShellState(documentSession: session, lifecycle: lifecycle)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        try await ready(state); state.selectLayer(ids[0])
        let before = session.document, history = session.historySnapshot()
        var requests = 0
        let subscription = state.editCommitRequests.sink { request in requests += 1; request.reject() }
        defer { subscription.cancel() }
        state.refreshPreview()
        XCTAssertEqual(requests, 1); XCTAssertTrue(state.workspaceActionStatus.contains("paused"))
        let destination = fixture.url.appendingPathComponent("blocked-output")
        state.writeStaticBuild(to: destination, replacingExisting: false)
        XCTAssertEqual(requests, 2); XCTAssertTrue(state.workspaceActionStatus.contains("paused"))
        XCTAssertEqual(session.document, before)
        XCTAssertEqual(session.historySnapshot(), history)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    @MainActor private func ready(_ state: WorkspaceShellState) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while state.canvasRenderPlan?.identity.revision != state.documentSession.document.revision
                || state.canvasRenderPlan?.identity.viewportGeneration != state.viewportState.generation {
            guard ContinuousClock.now < deadline else { throw CocoaError(.coderReadCorrupt) }
            await Task.yield()
        }
    }

    @MainActor func testWorkspaceSaveBoundaryCommitsDraftOnceAndReopensExactResourceIntent() async throws {
        let (session, asset, bytes, ids) = try twoImageUseFixture(), fixture = try makeFixture()
        let lifecycle = DocumentLifecycleController(session: session, recoveryDirectory: fixture.url.appendingPathComponent("recovery"),
            autosaveDebouncer: ManualLifecycleAutosaveDebouncer())
        let state = WorkspaceShellState(documentSession: session, lifecycle: lifecycle)
        let descriptor = ProjectResourceDescriptor(id: asset.resourceID, filename: asset.originalFilename, mediaType: "image/png",
            byteCount: bytes.count, sha256: asset.contentHash)
        _ = try lifecycle.installingProjectResource(descriptor, data: bytes) {
            try session.execute(.renamePage(.init(pageID: session.document.pages[0].id, name: "Boundary fixture")))
        }
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        try await ready(state); state.selectLayer(ids[0])
        let before = session.document, historyCount = session.historySnapshot().undoEntries.count
        var draft: LayoutInspectorNumericDraft? = .init(text: "132", committed: "100", scope: state.layoutInspectorDraftScope)
        let subscription = state.editCommitRequests.sink { request in
            guard let current = draft else { return }
            guard current.canCommit(in: state.layoutInspectorDraftScope),
                  case .success(let value) = GeometryInspectorNumberParser.parse(current.text),
                  state.commitGeometryInspectorValue(value, field: .height, provenance: .pointer, draftScope: current.scope) else {
                request.reject(); return
            }
            draft = nil
        }
        defer { subscription.cancel() }
        XCTAssertTrue(state.prepareForWorkspaceAction(.save), state.lastGeometryInspectorAnnouncement)
        XCTAssertNil(draft)
        let committed = session.document
        XCTAssertEqual(committed.pages[0].nodes.first { $0.id == ids[0] }?.insertionGeometry?.size.height, 132)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, historyCount + 1)
        XCTAssertTrue(state.prepareForWorkspaceAction(.save))
        XCTAssertEqual(session.historySnapshot().undoEntries.count, historyCount + 1)
        let package = fixture.url.appendingPathComponent("Boundary.siteforge")
        let saved = await lifecycle.save(to: package); XCTAssertTrue(saved)
        let reader = DocumentLifecycleController(session: DocumentSession(), recoveryDirectory: fixture.url.appendingPathComponent("reopen-recovery"))
        let opened = await reader.requestOpen(package); XCTAssertEqual(opened, .completed)
        XCTAssertEqual(reader.session.document, committed)
        XCTAssertEqual(try reader.projectResourceData(for: asset.resourceID), bytes)
        XCTAssertEqual(reader.session.document.imageAssets[0].organization, asset.organization)
        try session.undo(); XCTAssertEqual(session.document.pages, before.pages)
        try session.redo(); XCTAssertEqual(session.document.pages, committed.pages)
        XCTAssertEqual(try lifecycle.projectResourceData(for: asset.resourceID), bytes)
        // Numeric Desktop editing must not erase inherited automatic intent or
        // the deliberate Mobile width, fit, focal point and alt properties.
        let original = try XCTUnwrap(before.pages[0].nodes.first { $0.id == ids[0] })
        let changed = try XCTUnwrap(committed.pages[0].nodes.first { $0.id == ids[0] })
        XCTAssertEqual(original.properties.filter { $0.key.rawValue != "layout.height" }, changed.properties.filter { $0.key.rawValue != "layout.height" })
    }

    @MainActor func testWorkspaceInvalidOrStaleDraftBlocksContextPreviewAndCloseUntilCancelled() async throws {
        let (session, _, _, ids) = try twoImageUseFixture(), fixture = try makeFixture()
        let lifecycle = DocumentLifecycleController(session: session, recoveryDirectory: fixture.url.appendingPathComponent("recovery"))
        let state = WorkspaceShellState(documentSession: session, lifecycle: lifecycle)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        try await ready(state); state.selectLayer(ids[0])
        XCTAssertTrue(state.selectInspectorTab(.layout))
        var draft: LayoutInspectorNumericDraft? = .init(text: "-", committed: "160", scope: state.layoutInspectorDraftScope)
        let subscription = state.editCommitRequests.sink { request in
            guard let current = draft else { return }
            guard current.canCommit(in: state.layoutInspectorDraftScope),
                  case .success = GeometryInspectorNumberParser.parse(current.text) else { request.reject(); return }
        }
        defer { subscription.cancel() }
        let before = session.document, selection = state.selectionState.orderedIDs, tab = state.inspectorTab
        let otherSession = DocumentSession(document: before)
        let otherLifecycle = DocumentLifecycleController(session: otherSession, recoveryDirectory: fixture.url.appendingPathComponent("other-scene-recovery"))
        let otherScene = WorkspaceShellState(documentSession: otherSession, lifecycle: otherLifecycle)
        XCTAssertNotEqual(otherScene.viewportState.sceneID, state.viewportState.sceneID)
        XCTAssertTrue(otherScene.prepareForWorkspaceAction(.save), "Same document identity in another window must not commit or reject this scene's draft")
        XCTAssertNotNil(draft)
        for action in [WorkspaceEditCommitRequest.Action.save, .saveAs, .preview, .context, .close] {
            XCTAssertFalse(state.prepareForWorkspaceAction(action)); XCTAssertTrue(state.workspaceActionStatus.contains("paused"))
        }
        state.reviewBreakpoint(.mobile); XCTAssertEqual(state.viewportPreset, .desktop)
        state.selectLayer(ids[1]); XCTAssertEqual(state.selectionState.orderedIDs, selection)
        state.selectPage(session.document.pages[1].id)
        XCTAssertEqual(state.effectiveSelectedPageID, before.pages[0].id)
        state.performDefaultInsertion(.frame, provenance: .menu)
        XCTAssertEqual(session.document, before)
        XCTAssertFalse(state.selectInspectorTab(.design)); XCTAssertEqual(state.inspectorTab, tab)
        state.openBrowserPreview(); XCTAssertFalse(state.isBrowserPreviewPresented)
        XCTAssertEqual(session.document, before)
        draft = .init(text: "182", committed: "160", scope: state.layoutInspectorDraftScope)
        // An external context replacement, unlike an allowed UI switch, must
        // still reject the old draft rather than rebase it to the new target.
        state.viewportPreset = .mobile
        XCTAssertFalse(state.prepareForWorkspaceAction(.save))
        draft = nil // The same explicit cancellation performed by Escape.
        XCTAssertTrue(state.prepareForWorkspaceAction(.context))
        XCTAssertTrue(state.workspaceActionStatus.isEmpty)
        XCTAssertEqual(session.document, before)
        state.openPresentationMode()
        XCTAssertFalse(state.isPreviewPresented, "A matching document revision alone must not accept the old Desktop viewport")
        XCTAssertFalse(state.isPresentationMode)
        try await ready(state)
        XCTAssertTrue(state.openPreview())
        state.closePreview()
    }

    @MainActor func testWorkspaceInlineCommitBoundaryPreservesMarkedTextAndExactHistory() async throws {
        let fixture = try makeFixture(), session = DocumentSession(document: ProjectCreation.blank())
        let lifecycle = DocumentLifecycleController(session: session, recoveryDirectory: fixture.url.appendingPathComponent("recovery"))
        let state = WorkspaceShellState(documentSession: session, lifecycle: lifecycle)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        try await ready(state); state.performDefaultInsertion(.text, provenance: .menu); try await ready(state)
        let id = try XCTUnwrap(state.selectionState.primaryID), before = session.document
        let historyCount = session.historySnapshot().undoEntries.count
        XCTAssertTrue(state.beginTextEditing(nodeID: id, provenance: .menu))
        state.updateTextEditingDraft(text: "Keep this edit", selection: .init(location: 14, length: 0), markedRange: nil)
        XCTAssertTrue(state.prepareForWorkspaceAction(.save))
        XCTAssertFalse(state.textEditingSession.isActive)
        let committed = session.document
        XCTAssertEqual(committed.pages[0].nodes.first { $0.id == id }?.insertionStringProperty("content.text"), "Keep this edit")
        XCTAssertEqual(session.historySnapshot().undoEntries.count, historyCount + 1)
        try await ready(state)
        XCTAssertTrue(state.beginTextEditing(nodeID: id, provenance: .menu))
        state.updateTextEditingDraft(text: "Composition", selection: .init(location: 11, length: 0), markedRange: .init(location: 0, length: 11))
        XCTAssertFalse(state.prepareForWorkspaceAction(.close))
        XCTAssertTrue(state.textEditingSession.isActive)
        XCTAssertEqual(session.document, committed)
        state.cancelTextEditing(); XCTAssertTrue(state.prepareForWorkspaceAction(.close))
        try session.undo(); XCTAssertEqual(session.document.pages, before.pages)
        try session.redo(); XCTAssertEqual(session.document.pages, committed.pages)
    }

    @MainActor func testSavePanelRejectsChangedOriginAndQueuedReplacementBeforeWriting() async throws {
        let fixture = try makeFixture(), session = DocumentSession(document: ProjectCreation.blank())
        let destination = fixture.url.appendingPathComponent("Chosen.siteforge")
        var mutateInsidePanel = true
        let lifecycle = DocumentLifecycleController(session: session, recoveryDirectory: fixture.url.appendingPathComponent("recovery"),
            saveDestinationProvider: { _ in
                if mutateInsidePanel {
                    do { try session.execute(.renamePage(.init(pageID: session.document.pages[0].id, name: "Changed while panel open"))) }
                    catch { XCTFail("Fixture mutation must succeed") }
                }
                return destination
            })
        XCTAssertNil(lifecycle.presentSavePanel())
        XCTAssertTrue(lifecycle.fileActionNotice?.contains("document changed") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        mutateInsidePanel = false
        let queued = try XCTUnwrap(lifecycle.presentSavePanel())
        try session.establishBaseline(ProjectCreation.blank())
        let staleSaved = await queued.value
        XCTAssertFalse(staleSaved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertNil(lifecycle.fileURL)
        XCTAssertNil(lifecycle.fileActionNotice, "The old panel must not publish into the replacement document")
        let current = DocumentLifecycleController(session: DocumentSession(document: session.document),
            recoveryDirectory: fixture.url.appendingPathComponent("new-recovery"), saveDestinationProvider: { _ in destination })
        let accepted = try XCTUnwrap(current.presentSavePanel())
        let saved = await accepted.value; XCTAssertTrue(saved)
        let reopened = try await ProjectPackageStore().read(from: destination)
        XCTAssertEqual(reopened.document, current.session.document)
        XCTAssertEqual(current.statusText, "Saved")
    }

    @MainActor func testOpenPanelRejectsChangedOriginWithoutOpeningOrReplacingCurrentLifecycle() throws {
        let fixture = try makeFixture(), session = DocumentSession(document: ProjectCreation.blank())
        let lifecycle = DocumentLifecycleController(session: session, recoveryDirectory: fixture.url.appendingPathComponent("recovery"))
        let launch = LaunchExperienceController(lifecycle: lifecycle, previewScenario: nil)
        let chosen = fixture.url.appendingPathComponent("NotOpened.siteforge")
        let before = session.document
        XCTAssertFalse(launch.presentOpenPanel(chooseProject: {
            do { try session.execute(.renamePage(.init(pageID: session.document.pages[0].id, name: "Kept new edit"))) }
            catch { XCTFail("Fixture mutation must succeed") }
            return chosen
        }))
        XCTAssertEqual(session.document.id, before.id)
        XCTAssertEqual(session.document.pages[0].name, "Kept new edit")
        XCTAssertTrue(lifecycle.fileActionNotice?.contains("Open paused") == true)
        XCTAssertNil(lifecycle.fileURL)
        let unchanged = session.document
        XCTAssertFalse(launch.presentOpenPanel(chooseProject: { nil }))
        XCTAssertEqual(session.document, unchanged)
        XCTAssertFalse(FileManager.default.fileExists(atPath: chosen.path))
    }

    @MainActor private func twoImageUseFixture() throws -> (DocumentSession, ImageAsset, Data, [NodeID]) {
        let bytes = try makePNG(width: 7, height: 5)
        let asset = ImageAsset(resourceID: ResourceID(), displayName: "Original", originalFilename: "original.png", format: .png,
            pixelWidth: 7, pixelHeight: 5, byteCount: bytes.count, contentHash: ProjectResourceStore.digest(bytes),
            organization: try .init(folderPath: "Pictures", tags: ["hero"], favorite: true))
        let session = DocumentSession()
        try session.execute(.insertImageAsset(.init(asset: asset, index: 0)))
        let page = session.document.pages[0], rootID = page.rootNodeIDs[0]
        var ids: [NodeID] = []
        for index in 0..<2 {
            let id = NodeID(); ids.append(id)
            let node = DocumentNode(id: id, kind: .image, name: "Image \(index)", parent: .node(rootID), properties: [
                .init(key: .init(rawValue: "layout.x"), value: .number(Double(index * 200))),
                .init(key: .init(rawValue: "layout.y"), value: .number(40)),
                .init(key: .init(rawValue: "layout.width"), value: .number(160)),
                .init(key: .init(rawValue: "layout.height"), value: .number(100)),
                .init(key: .init(rawValue: CanonicalSizingConstraints.prefix + "widthMode"), value: .string("fill")),
                .init(key: .init(rawValue: ResponsiveGeometryResolver.key(.width, breakpoint: .mobile)), value: .number(140)),
                .init(key: .init(rawValue: CanonicalImageStyle.namespace + "assetID"), value: .string(asset.id.description)),
                .init(key: .init(rawValue: CanonicalImageStyle.namespace + "fit"), value: .string("fill")),
                .init(key: .init(rawValue: CanonicalImageStyle.namespace + "focal.x"), value: .number(0.3)),
                .init(key: .init(rawValue: CanonicalImageStyle.namespace + "focal.y"), value: .number(0.7)),
                .init(key: .init(rawValue: CanonicalImageStyle.namespace + "alt"), value: .string("Original alt")),
                .init(key: .init(rawValue: CanonicalImageStyle.namespace + "decorative"), value: .boolean(false))])
            try session.execute(.insertNode(.init(pageID: page.id, node: node, index: index)))
        }
        return (session, asset, bytes, ids)
    }

    @MainActor private func imageDetailsEdit(_ edit: ImageInspectorEdit, session: DocumentSession,
                                            ids: [NodeID], cancelled: Bool = false) throws -> PreparedImageInspectorEdit {
        let page = session.document.pages[0], scene = CanvasViewportSceneID()
        let context = TransformValidationContext(activePageID: page.id, currentSceneID: scene,
            rendererGeneration: session.document.revision, selectedNodeIDs: ids, availableNodeIDs: Set(ids),
            isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        let identity = ImageInspectorOperationIdentity(documentID: session.document.id, pageID: page.id,
            revision: session.document.revision, sceneID: scene, rendererGeneration: session.document.revision, selectedNodeIDs: ids)
        return try ImageInspectorCommandRegistry().prepare(.init(identity: identity, edit: edit),
            in: session.document, context: context, cancelled: cancelled)
    }

    // SF-0802-003/006: asset identity is not a reason to hide a common fit or
    // borrow a primary description/focal coordinate from a mixed selection.
    @MainActor func testImageInspectorProjectsEachMixedPropertyWithoutPrimaryBorrowing() throws {
        let (session, original, _, ids) = try twoImageUseFixture()
        let bytes = try makePNG(width: 9, height: 6)
        let other = ImageAsset(resourceID: ResourceID(), displayName: "Other", originalFilename: "other.png", format: .png,
            pixelWidth: 9, pixelHeight: 6, byteCount: bytes.count, contentHash: ProjectResourceStore.digest(bytes))
        try session.execute(.insertImageAsset(.init(asset: other, index: 1)))
        try session.execute(try imageDetailsEdit(.asset(other.id), session: session, ids: [ids[1]]).command)
        var selection = try XCTUnwrap(ImageInspectorSelection(nodes: session.document.pages[0].nodes))
        XCTAssertNil(selection.assetID); XCTAssertEqual(selection.fit, .fill)
        XCTAssertEqual(selection.focalX, 0.3); XCTAssertEqual(selection.altText, "Original alt")
        XCTAssertEqual(selection.applicableCount, 2); XCTAssertEqual(selection.skippedCount, 1)
        try session.execute(try imageDetailsEdit(.focal(x: 0.333333, y: 0.666667), session: session, ids: ids).command)
        selection = try XCTUnwrap(ImageInspectorSelection(nodes: session.document.pages[0].nodes))
        XCTAssertEqual(try selection.detailsEdit(focalXDraft: nil, focalYDraft: "80", altDraft: nil),
            .details(focalX: 0.333333, focalY: 0.8, altText: nil), "Do not round an untouched coordinate from its displayed percentage")
        try session.execute(try imageDetailsEdit(.details(focalX: 0.9, focalY: 0.2, altText: "Different"), session: session, ids: [ids[1]]).command)
        selection = try XCTUnwrap(ImageInspectorSelection(nodes: session.document.pages[0].nodes))
        XCTAssertNil(selection.focalX); XCTAssertNil(selection.focalY); XCTAssertNil(selection.altText)
        XCTAssertThrowsError(try selection.detailsEdit(focalXDraft: "20", focalYDraft: nil, altDraft: nil))
        XCTAssertEqual(try selection.detailsEdit(focalXDraft: "20", focalYDraft: "80", altDraft: "Common"),
            .details(focalX: 0.2, focalY: 0.8, altText: "Common"))
        for invalid in ["", "-", "nan", "inf", "101"] {
            XCTAssertThrowsError(try selection.detailsEdit(focalXDraft: invalid, focalYDraft: "80", altDraft: nil))
        }
        XCTAssertEqual(selection.decorative, false); XCTAssertEqual(selection.fit, .fill)
        XCTAssertEqual(session.document.imageAssets.first, original)
        XCTAssertNil(ImageInspectorSelection(nodes: [session.document.pages[0].nodes[0]]))
    }

    // SF-0802-002/005, SF-0807-003/005: drafts compile into one existing
    // property transaction; no asset/reference/geometry is rewritten.
    @MainActor func testImageDetailsDraftBatchIsAtomicNeutralAndExactlyReversible() throws {
        let (session, asset, _, ids) = try twoImageUseFixture()
        let before = session.document, count = session.historySnapshot().undoEntries.count
        let selection = ids + session.document.pages[0].rootNodeIDs
        let edit = ImageInspectorEdit.details(focalX: 0.1, focalY: 0.9, altText: "A <figure> & caption")
        let prepared = try imageDetailsEdit(edit, session: session, ids: selection)
        XCTAssertEqual(prepared.applicableNodeIDs, ids)
        XCTAssertEqual(prepared.skippedNodeIDs, session.document.pages[0].rootNodeIDs)
        try session.execute(prepared.command)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, count + 1)
        let committed = session.document
        for id in ids {
            let old = try XCTUnwrap(before.pages[0].nodes.first { $0.id == id })
            let next = try XCTUnwrap(committed.pages[0].nodes.first { $0.id == id })
            XCTAssertEqual(next.id, old.id); XCTAssertEqual(next.insertionGeometry, old.insertionGeometry)
            for suffix in ["focal.x", "focal.y", "alt"] {
                XCTAssertEqual(next.insertionProperty(CanonicalImageStyle.namespace + suffix)?.id,
                    old.insertionProperty(CanonicalImageStyle.namespace + suffix)?.id)
            }
            XCTAssertEqual(CanonicalImageStyle.resolve(next)?.assetID, asset.id)
            XCTAssertEqual(CanonicalImageStyle.resolve(next)?.fitMode, .fill)
        }
        XCTAssertEqual(ImageAssetReference.references(to: asset.id, in: committed), ImageAssetReference.references(to: asset.id, in: before))
        if case .batch(let commands) = try imageDetailsEdit(edit, session: session, ids: selection).command {
            XCTAssertTrue(commands.isEmpty)
        } else { XCTFail("Repeated authored values must be history-neutral") }
        for invalid in [ImageInspectorEdit.details(focalX: 0.2, focalY: nil, altText: "ignored"),
                        .details(focalX: .nan, focalY: 0.5, altText: nil),
                        .details(focalX: nil, focalY: nil, altText: String(repeating: "x", count: 4097))] {
            XCTAssertThrowsError(try imageDetailsEdit(invalid, session: session, ids: selection))
            XCTAssertEqual(session.document, committed)
        }
        XCTAssertThrowsError(try imageDetailsEdit(.fit(.stretch), session: session, ids: ids, cancelled: true)) {
            XCTAssertEqual($0 as? ImageInspectorError, .cancelled)
        }
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(committed)), committed)
        try session.undo(); XCTAssertEqual(session.document.pages, before.pages)
        try session.redo(); XCTAssertEqual(session.document.pages, committed.pages)
        try session.execute(try imageDetailsEdit(.decorative(true), session: session, ids: ids).command)
        for id in ids {
            let style = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == id }.flatMap(CanonicalImageStyle.resolve))
            XCTAssertTrue(style.isDecorative); XCTAssertEqual(style.altText, "A <figure> & caption")
        }
        try session.undo(); XCTAssertEqual(session.document.pages, committed.pages)
    }

    // SF-0801-004/005, SF-0802-003/005/006: current snapshot status, stale
    // drafts, no-op history, original bytes and renderer/output agree.
    @MainActor func testImageDraftOwnershipMissingRecoveryAndOutputPreserveOriginalResource() async throws {
        let (session, asset, bytes, ids) = try twoImageUseFixture(), fixture = try makeFixture()
        let lifecycle = DocumentLifecycleController(session: session, recoveryDirectory: fixture.url.appendingPathComponent("image-draft-recovery"),
            autosaveDebouncer: ManualLifecycleAutosaveDebouncer())
        let state = WorkspaceShellState(documentSession: session, lifecycle: lifecycle)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        try await ready(state); state.selectLayer(ids[0])
        XCTAssertTrue(state.imageInspectorResourceStatus.contains("unavailable"))
        let opening = state.responsiveInspectorEditContext
        let draft = ImageInspectorDraft(text: "A retained description", openingText: "Original alt", context: opening)
        XCTAssertTrue(draft.canCommit(in: opening)); XCTAssertFalse(draft.isUnchanged)
        let descriptor = ProjectResourceDescriptor(id: asset.resourceID, filename: asset.originalFilename, mediaType: "image/png",
            byteCount: bytes.count, sha256: asset.contentHash)
        _ = try lifecycle.installingProjectResource(descriptor, data: bytes) {
            try session.execute(.renamePage(.init(pageID: session.document.pages[0].id, name: "Resource restored")))
        }
        try await ready(state)
        XCTAssertFalse(draft.canCommit(in: state.responsiveInspectorEditContext))
        let before = session.document
        XCTAssertFalse(state.commitImageInspectorEdit(.altText(draft.text), expectedContext: draft.context))
        XCTAssertEqual(session.document, before)
        state.cancelImageInspectorDraft()
        XCTAssertEqual(session.document, before)
        XCTAssertFalse(state.imageInspectorResourceStatus.contains("unavailable"))
        let context = state.responsiveInspectorEditContext
        XCTAssertTrue(state.commitImageInspectorEdit(.details(focalX: 0.2, focalY: 0.8, altText: "A <figure> & caption"), expectedContext: context))
        try await ready(state)
        let history = session.historySnapshot().undoEntries.count
        XCTAssertTrue(state.commitImageInspectorEdit(.details(focalX: 0.2, focalY: 0.8, altText: "A <figure> & caption"), expectedContext: state.responsiveInspectorEditContext))
        XCTAssertEqual(session.historySnapshot().undoEntries.count, history)
        let object = try XCTUnwrap(state.canvasRenderPlan?.authoredObjects.first { $0.id == ids[0] })
        XCTAssertEqual(object.imageAssetID, asset.id); XCTAssertNotNil(object.imageData)
        XCTAssertEqual(object.imageFocalX, 0.2); XCTAssertEqual(object.imageFocalY, 0.8)
        let output = try MultiPageStaticBuildPlanner.plan(document: session.document)
        let markup = output.files.map(\.contents).joined(separator: "\n")
        XCTAssertTrue(markup.contains("A &lt;figure&gt; &amp; caption"))
        XCTAssertTrue(markup.contains("object-fit: cover"))
        XCTAssertEqual(try lifecycle.projectResourceData(for: asset.resourceID), bytes)
        let saved = session.document, package = fixture.url.appendingPathComponent("ImageDraft.siteforge")
        let didSave = await lifecycle.save(to: package); XCTAssertTrue(didSave)
        let reader = DocumentLifecycleController(session: DocumentSession(), recoveryDirectory: fixture.url.appendingPathComponent("image-reader-recovery"))
        let opened = await reader.requestOpen(package); XCTAssertEqual(opened, .completed)
        XCTAssertEqual(reader.session.document, saved)
        XCTAssertEqual(try reader.projectResourceData(for: asset.resourceID), bytes)
    }

    // SF-0807-002/003/004/006: a filtered navigator cannot hide reusable
    // project images from the chooser or force a duplicate import.
    @MainActor func testImageReuseSearchIsIndependentAndClearFiltersIsNoncanonical() async throws {
        let (session, asset, _, _) = try twoImageUseFixture(), fixture = try makeFixture()
        let state = WorkspaceShellState(documentSession: session, lifecycle: .init(session: session,
            recoveryDirectory: fixture.url.appendingPathComponent("reuse-search-recovery")))
        let before = session.document, history = session.historySnapshot().undoEntries.count
        state.assetSearchText = "not-present"; state.assetFavoritesOnly = true
        state.assetFolderFilter = "Absent"; state.assetTagFilter = "Absent"
        XCTAssertTrue(state.imageAssets.isEmpty)
        XCTAssertEqual(state.imageAssetsForReuse(search: "  HERO  ").map(\.id), [asset.id])
        XCTAssertEqual(state.imageAssetsForReuse(search: "original.png").map(\.id), [asset.id])
        XCTAssertTrue(state.imageAssetsForReuse(search: "no match").isEmpty)
        XCTAssertEqual(state.assetSearchText, "not-present")
        state.clearImageAssetFilters()
        XCTAssertEqual(state.imageAssets.map(\.id), [asset.id])
        XCTAssertEqual(session.document, before); XCTAssertEqual(session.historySnapshot().undoEntries.count, history)
        let corrupt = fixture.url.appendingPathComponent("corrupt-image.png")
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: corrupt)
        do {
            _ = try await ImageImportWorker().prepare(url: corrupt)
            XCTFail("Corrupt input must not produce an import candidate")
        } catch { XCTAssertTrue(error is ImageImportError) }
        XCTAssertEqual(session.document, before)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, history)
    }

    @MainActor func testSelectedImageImportIsAtomicLocalDeduplicatedAndReopensWithOriginalBytes() async throws {
        let (session, original, originalBytes, ids) = try twoImageUseFixture(), fixture = try makeFixture()
        let debouncer = ManualLifecycleAutosaveDebouncer(), scene = CanvasViewportSceneID()
        let lifecycle = DocumentLifecycleController(session: session, recoveryDirectory: fixture.url.appendingPathComponent("recovery"), autosaveDebouncer: debouncer)
        let originalDescriptor = ProjectResourceDescriptor(id: original.resourceID, filename: original.originalFilename,
            mediaType: "image/png", byteCount: originalBytes.count, sha256: original.contentHash)
        _ = try lifecycle.installingProjectResource(originalDescriptor, data: originalBytes) {
            try session.execute(.renamePage(.init(pageID: session.document.pages[0].id, name: "Asset use fixture")))
        }
        func request() -> ImageAssetUseRequest {
            .init(identity: .init(documentID: session.document.id, pageID: session.document.pages[0].id, revision: session.document.revision,
                sceneID: scene, rendererGeneration: session.document.revision, selectedNodeIDs: [ids[0]]), target: .image)
        }
        func context() -> TransformValidationContext {
            .init(activePageID: session.document.pages[0].id, currentSceneID: scene, rendererGeneration: session.document.revision,
                selectedNodeIDs: [ids[0]], availableNodeIDs: Set(ids), isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        }
        let url = fixture.url.appendingPathComponent("replacement.png"), newBytes = try makePNG(width: 11, height: 9)
        try newBytes.write(to: url)
        let imported = try await ImageImportWorker().prepare(url: url), before = session.document
        let prepared = try ImageInspectorCommandRegistry().prepareImportedAssetUse(imported, request: request(), in: before, context: context())
        let count = session.historySnapshot().undoEntries.count
        _ = try lifecycle.installingProjectResource(imported.descriptor, data: imported.data) { try session.execute(prepared.command) }
        XCTAssertEqual(session.historySnapshot().undoEntries.count, count + 1)
        XCTAssertEqual(session.document.imageAssets.first { $0.id == original.id }, original)
        let first = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == ids[0] })
        let second = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == ids[1] })
        XCTAssertEqual(CanonicalImageStyle.resolve(first)?.assetID, imported.asset.id)
        XCTAssertEqual(CanonicalImageStyle.resolve(second)?.assetID, original.id)
        let previous = try XCTUnwrap(before.pages[0].nodes.first { $0.id == ids[0] })
        XCTAssertEqual(first.properties.filter { $0.key.rawValue != CanonicalImageStyle.namespace + "assetID" }, previous.properties.filter { $0.key.rawValue != CanonicalImageStyle.namespace + "assetID" })
        XCTAssertEqual(first.insertionProperty(CanonicalImageStyle.namespace + "assetID")?.id, previous.insertionProperty(CanonicalImageStyle.namespace + "assetID")?.id)
        let committed = session.document
        try session.undo(); XCTAssertEqual(session.document.pages, before.pages); XCTAssertEqual(session.document.imageAssets, before.imageAssets)
        try session.redo(); XCTAssertEqual(session.document.pages, committed.pages)
        let duplicate = try ImageInspectorCommandRegistry().prepareImportedAssetUse(imported, request: request(), in: session.document, context: context())
        XCTAssertFalse(duplicate.installsResource)
        if case .batch(let commands) = duplicate.command { XCTAssertTrue(commands.isEmpty) } else { XCTFail("Reusing the same image is neutral") }
        let project = fixture.url.appendingPathComponent("Images.siteforge")
        let saved = await lifecycle.save(to: project); XCTAssertTrue(saved)
        let reader = DocumentLifecycleController(session: DocumentSession(), recoveryDirectory: fixture.url.appendingPathComponent("recovery"))
        let opened = await reader.requestOpen(project); XCTAssertEqual(opened, .completed)
        XCTAssertEqual(reader.session.document, session.document)
        XCTAssertEqual(try reader.projectResourceData(for: original.resourceID), originalBytes)
        XCTAssertEqual(try reader.projectResourceData(for: imported.asset.resourceID), newBytes)
        let reset = try ImageInspectorCommandRegistry().prepareAssetUse(original.id, request: request(), in: session.document, context: context())
        try session.execute(reset)
        await debouncer.waitUntilPending(); debouncer.fireAll()
        while lifecycle.hasPendingAutosaveWork { await Task.yield() }
        let recovered = DocumentLifecycleController(session: DocumentSession(), recoveryDirectory: fixture.url.appendingPathComponent("recovery"))
        let recoveryOpen = await recovered.requestOpen(project); XCTAssertEqual(recoveryOpen, .completed)
        let restored = await recovered.requestRestoreRecovery(); XCTAssertEqual(restored, .completed)
        XCTAssertEqual(recovered.session.document.pages, session.document.pages)
        try recovered.session.undo(); XCTAssertEqual(recovered.session.document.pages, committed.pages)
        XCTAssertEqual(try recovered.projectResourceData(for: imported.asset.resourceID), newBytes)
    }

    @MainActor func testSelectedImageDecodeCompletionRejectsStaleSelectionAndCancellation() async throws {
        let (session, _, _, ids) = try twoImageUseFixture(), fixture = try makeFixture(), scene = CanvasViewportSceneID()
        let identity = ImageInspectorOperationIdentity(documentID: session.document.id, pageID: session.document.pages[0].id,
            revision: session.document.revision, sceneID: scene, rendererGeneration: session.document.revision, selectedNodeIDs: [ids[0]])
        let request = ImageAssetUseRequest(identity: identity, target: .image)
        let url = fixture.url.appendingPathComponent("new.png"); try makePNG(width: 13, height: 8).write(to: url)
        let imported = try await ImageImportWorker().prepare(url: url)
        let changed = TransformValidationContext(activePageID: identity.pageID, currentSceneID: scene, rendererGeneration: identity.rendererGeneration,
            selectedNodeIDs: [ids[1]], availableNodeIDs: Set(ids), isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        let before = session.document
        XCTAssertThrowsError(try ImageInspectorCommandRegistry().prepareImportedAssetUse(imported, request: request, in: before, context: changed))
        XCTAssertThrowsError(try ImageInspectorCommandRegistry().prepareImportedAssetUse(nil, request: request, in: before, context: changed)) { XCTAssertEqual($0 as? ImageImportError, .cancelled) }
        XCTAssertEqual(session.document, before)
        XCTAssertEqual(session.document.imageAssets.count, 1)
    }

    @MainActor func testAssetUsageRevealWaitsForActualFillReferencePageAdoption() async throws {
        let (_, asset, _, _) = try twoImageUseFixture()
        var document = ProjectCreation.blank()
        document.imageAssets = [asset]
        var page = DocumentPage.minimum(name: "Other", route: "/other", role: .standard, provenance: .authored)
        let fill = DocumentNode(kind: .frame, name: "Only fill reference", parent: .node(page.rootNodeIDs[0]), properties: [
            .init(key: .init(rawValue: "layout.x"), value: .number(20)), .init(key: .init(rawValue: "layout.y"), value: .number(20)),
            .init(key: .init(rawValue: "layout.width"), value: .number(200)), .init(key: .init(rawValue: "layout.height"), value: .number(120)),
            .init(key: .init(rawValue: CanonicalImageFill.assetKey), value: .string(asset.id.description))])
        page.nodes[0].childIDs = [fill.id]; page.nodes.append(fill); document.pages.append(page)
        try document.validate()
        let session = DocumentSession(document: document), fixture = try makeFixture()
        let lifecycle = DocumentLifecycleController(session: session, recoveryDirectory: fixture.url.appendingPathComponent("recovery"))
        let state = WorkspaceShellState(documentSession: session, lifecycle: lifecycle)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        state.revealImageUsage(asset.id)
        let deadline = ContinuousClock.now + .seconds(3)
        while state.selectionState.orderedIDs != [fill.id], ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertEqual(state.effectiveSelectedPageID, page.id)
        XCTAssertEqual(state.selectionState.orderedIDs, [fill.id])
        XCTAssertEqual(state.navigatorTab, .layers)
        XCTAssertEqual(state.imageAssetUsageCount(asset.id), 1)
        XCTAssertEqual(session.document, document)
    }

    @MainActor func testSharedAssetThumbnailTracksReplacementUndoAndRedoResourceIdentity() async throws {
        let (session, original, originalBytes, _) = try twoImageUseFixture()
        let fixture = try makeFixture()
        let lifecycle = DocumentLifecycleController(session: session, recoveryDirectory: fixture.url.appendingPathComponent("recovery"))
        let state = WorkspaceShellState(documentSession: session, lifecycle: lifecycle)
        let descriptor = ProjectResourceDescriptor(id: original.resourceID, filename: original.originalFilename, mediaType: "image/png",
            byteCount: originalBytes.count, sha256: original.contentHash)
        _ = try state.lifecycle.installingProjectResource(descriptor, data: originalBytes) {
            try session.execute(.renamePage(.init(pageID: session.document.pages[0].id, name: "Thumbnail fixture")))
        }
        let oldThumbnail = try await ImageThumbnailWorker().thumbnailPNG(from: originalBytes)
        func awaitThumbnail(_ expected: Data) async {
            let deadline = ContinuousClock.now + .seconds(3)
            while state.imageAssetThumbnail(original.id) != expected, ContinuousClock.now < deadline { await Task.yield() }
            XCTAssertEqual(state.imageAssetThumbnail(original.id), expected)
        }
        await awaitThumbnail(oldThumbnail)
        let url = fixture.url.appendingPathComponent("new-thumbnail.png")
        try makePNG(width: 11, height: 9).write(to: url)
        let imported = try await ImageImportWorker().prepare(url: url)
        var replacement = original
        replacement.resourceID = imported.asset.resourceID; replacement.contentHash = imported.asset.contentHash
        replacement.pixelWidth = imported.asset.pixelWidth; replacement.pixelHeight = imported.asset.pixelHeight
        replacement.byteCount = imported.asset.byteCount; replacement.originalFilename = imported.asset.originalFilename
        _ = try state.lifecycle.installingProjectResource(imported.descriptor, data: imported.data) {
            try session.execute(.updateImageAsset(.init(asset: replacement)))
        }
        let newThumbnail = try await ImageThumbnailWorker().thumbnailPNG(from: imported.data)
        XCTAssertNotEqual(oldThumbnail, newThumbnail)
        await awaitThumbnail(newThumbnail)
        try session.undo(); await awaitThumbnail(oldThumbnail)
        try session.redo(); await awaitThumbnail(newThumbnail)
        XCTAssertEqual(session.document.imageAssets[0].organization, original.organization)
        XCTAssertEqual(try state.lifecycle.projectResourceData(for: original.resourceID), originalBytes)
    }

    func testAssetOrganizationNormalizesAndRejectsInvalidFoldersAndTags() throws {
        let value = try AssetOrganization(folderPath: " Campaign / Summer ",
                                          tags: [" hero ", "Detail"], favorite: true)
        XCTAssertEqual(value.folderPath, "Campaign/Summer")
        XCTAssertEqual(value.tags, ["Detail", "hero"])
        XCTAssertTrue(value.favorite)
        XCTAssertThrowsError(try AssetOrganization(folderPath: "../../private"))
        XCTAssertThrowsError(try AssetOrganization(folderPath: "A//B"))
        XCTAssertThrowsError(try AssetOrganization(tags: ["hero", "HERO"]))
        XCTAssertThrowsError(try AssetOrganization(tags: [String(repeating: "x", count: 33)]))
        XCTAssertThrowsError(try AssetOrganization(tags: Array(repeating: "x", count: 13)))
    }

    @MainActor
    func testAssetOrganizationRegistryGuardsIdentityAndPreservesExactHistory() throws {
        let bytes = try makePNG(width: 3, height: 2)
        let asset = ImageAsset(resourceID: ResourceID(), displayName: "Hero", originalFilename: "hero.png",
            format: .png, pixelWidth: 3, pixelHeight: 2, byteCount: bytes.count,
            contentHash: ProjectResourceStore.digest(bytes))
        let session = DocumentSession()
        try session.execute(.insertImageAsset(.init(asset: asset, index: 0)))
        let scene = CanvasViewportSceneID()
        let first = AssetOrganizationEditIdentity(documentID: session.document.id,
            revision: session.document.revision, assetID: asset.id, sceneID: scene)
        let registry = AssetOrganizationCommandRegistry()
        let edit = try registry.prepare(folder: "Campaign", tags: ["hero"], favorite: true,
            identity: first, live: first, document: session.document)
        try session.execute(edit)
        let organized = try XCTUnwrap(session.document.imageAssets.first)
        XCTAssertEqual(organized.id, asset.id)
        XCTAssertEqual(organized.resourceID, asset.resourceID)
        XCTAssertEqual(organized.organization?.folderPath, "Campaign")
        XCTAssertEqual(organized.organization?.tags, ["hero"])
        XCTAssertThrowsError(try registry.prepare(folder: "Other", tags: [], favorite: false,
            identity: first, live: first, document: session.document))
        let second = AssetOrganizationEditIdentity(documentID: session.document.id,
            revision: session.document.revision, assetID: asset.id, sceneID: scene)
        let otherScene = AssetOrganizationEditIdentity(documentID: session.document.id,
            revision: session.document.revision, assetID: asset.id, sceneID: CanvasViewportSceneID())
        XCTAssertThrowsError(try registry.prepare(folder: nil, tags: [], favorite: false,
            identity: second, live: otherScene, document: session.document))
        XCTAssertThrowsError(try registry.prepare(folder: nil, tags: [], favorite: false,
            identity: second, live: second, document: session.document, cancelled: true))
        XCTAssertThrowsError(try registry.prepare(folder: "Campaign", tags: ["hero"], favorite: true,
            identity: second, live: second, document: session.document))
        XCTAssertThrowsError(try registry.prepare(folder: nil, tags: ["hero", "HERO"], favorite: false,
            identity: second, live: second, document: session.document))
        XCTAssertEqual(session.document.imageAssets, [organized])
        try session.undo()
        XCTAssertEqual(session.document.imageAssets, [asset])
        try session.redo()
        XCTAssertEqual(session.document.imageAssets, [organized])
        let reopened = try DocumentSerializer.decode(DocumentSerializer.encode(session.document))
        XCTAssertEqual(reopened.imageAssets, [organized])
    }

    @MainActor
    func testSchemaTenAssetOrganizationMigrationAndVersionGuard() throws {
        let bytes = try makePNG(width: 2, height: 2)
        let asset = ImageAsset(resourceID: ResourceID(), displayName: "Legacy", originalFilename: "legacy.png",
            format: .png, pixelWidth: 2, pixelHeight: 2, byteCount: bytes.count,
            contentHash: ProjectResourceStore.digest(bytes))
        var original = ProjectCreation.blank()
        original.imageAssets = [asset]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(original)) as? [String: Any])
        object["schemaVersion"] = 10
        var legacyDocument = try XCTUnwrap(object["document"] as? [String: Any])
        legacyDocument.removeValue(forKey: "websiteMetadata")
        object["document"] = legacyDocument
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let migrated = try DocumentSerializer.decode(legacy)
        XCTAssertNil(migrated.imageAssets[0].organization)
        XCTAssertEqual(migrated.imageAssets[0].id, asset.id)
        var authored = migrated
        authored.imageAssets[0].organization = try AssetOrganization(folderPath: "Studio", tags: ["hero"], favorite: true)
        let reopened = try DocumentSerializer.decode(DocumentSerializer.encode(authored))
        XCTAssertEqual(reopened.imageAssets, authored.imageAssets)
        var invalid = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(authored)) as? [String: Any])
        var invalidDocument = try XCTUnwrap(invalid["document"] as? [String: Any])
        var invalidAssets = try XCTUnwrap(invalidDocument["imageAssets"] as? [[String: Any]])
        var invalidOrganization = try XCTUnwrap(invalidAssets[0]["organization"] as? [String: Any])
        invalidOrganization["unexpected"] = "not canonical"
        invalidAssets[0]["organization"] = invalidOrganization
        invalidDocument["imageAssets"] = invalidAssets
        invalid["document"] = invalidDocument
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: invalid)))
        var smuggled = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(authored)) as? [String: Any])
        smuggled["schemaVersion"] = 10
        var smuggledDocument = try XCTUnwrap(smuggled["document"] as? [String: Any])
        smuggledDocument.removeValue(forKey: "websiteMetadata")
        smuggled["document"] = smuggledDocument
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: smuggled)))
    }

    func testStaticImageOutputReferenceUsesOnlyVerifiedContentAddressedEntry() throws {
        let bytes = Data([0x89, 0x50, 0x4e, 0x47])
        let hash = ProjectResourceStore.digest(bytes)
        let asset = ImageAsset(resourceID: ResourceID(), displayName: "Card", originalFilename: "card.png", format: .png, pixelWidth: 1, pixelHeight: 1, byteCount: bytes.count, contentHash: hash)
        let entry = StaticAssetExportEntry(resourceID: asset.resourceID, outputPath: "assets/\(hash).png", sha256: hash)
        XCTAssertEqual(try StaticImageOutputReferencePlanner.path(for: asset, entries: [entry]), entry.outputPath)
        var organized = asset
        organized.organization = try AssetOrganization(folderPath: "Campaign", tags: ["hero"], favorite: true)
        XCTAssertEqual(try StaticImageOutputReferencePlanner.path(for: organized, entries: [entry]), entry.outputPath,
                       "Project-local organization must not alter the authored/static asset reference")
        XCTAssertThrowsError(try StaticImageOutputReferencePlanner.path(for: asset, entries: []))
    }
    @MainActor
    func testComponentDefinitionResourcesSurviveLinkedDuplicationSaveAndRecovery() async throws {
        let fixture = try makeFixture()
        let bytes = try makePNG(width: 4, height: 3)
        let descriptor = ProjectResourceDescriptor(id: ResourceID(), filename: "card.png", mediaType: "image/png",
            byteCount: bytes.count, sha256: ProjectResourceStore.digest(bytes))
        let asset = ImageAsset(resourceID: descriptor.id, displayName: "Card", originalFilename: "card.png",
            format: .png, pixelWidth: 4, pixelHeight: 3, byteCount: bytes.count, contentHash: descriptor.sha256)
        var document = ProjectCreation.blank()
        document.imageAssets = [asset]
        let pageID = document.pages[0].id, parentID = document.pages[0].rootNodeIDs[0]
        var frame = DocumentNode(kind: .frame, name: "Card", parent: .node(parentID), properties:
            [("layout.x", 80.0), ("layout.y", 90), ("layout.width", 240), ("layout.height", 160)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
            })
        let image = DocumentNode(kind: .image, name: "Photo", parent: .node(frame.id), properties: [
            NodeProperty(key: .init(rawValue: "content.image.v1.assetID"), value: .string(asset.id.description)),
            NodeProperty(key: .init(rawValue: "content.image.v1.fit"), value: .string(ImageFitMode.fit.rawValue), origin: .defaulted),
            NodeProperty(key: .init(rawValue: "content.image.v1.focal.x"), value: .number(0.5), origin: .defaulted),
            NodeProperty(key: .init(rawValue: "content.image.v1.focal.y"), value: .number(0.5), origin: .defaulted),
            NodeProperty(key: .init(rawValue: "content.image.v1.alt"), value: .string(""), origin: .defaulted),
            NodeProperty(key: .init(rawValue: "content.image.v1.decorative"), value: .boolean(false), origin: .defaulted),
            NodeProperty(key: .init(rawValue: "layout.x"), value: .number(100)),
            NodeProperty(key: .init(rawValue: "layout.y"), value: .number(110)),
            NodeProperty(key: .init(rawValue: "layout.width"), value: .number(80)),
            NodeProperty(key: .init(rawValue: "layout.height"), value: .number(60))
        ])
        let text = DocumentNode(kind: .text, name: "Caption", parent: .node(frame.id), properties: [
            .init(key: .init(rawValue: "content.text"), value: .string("Default caption")),
            .init(key: .init(rawValue: "layout.x"), value: .number(100)),
            .init(key: .init(rawValue: "layout.y"), value: .number(175)),
            .init(key: .init(rawValue: "layout.width"), value: .number(160)),
            .init(key: .init(rawValue: "layout.height"), value: .number(24))
        ])
        frame.childIDs = [image.id, text.id]
        document.pages[0].nodes[0].childIDs = [frame.id]
        document.pages[0].nodes += [frame, image, text]
        try document.validate()
        let session = DocumentSession(document: document), sceneID = CanvasViewportSceneID()
        let prepared = try ComponentCommandRegistry().prepare(.create(frame.id), identity: .init(
            documentID: document.id, pageID: pageID, revision: document.revision,
            sceneID: sceneID, rendererGeneration: document.revision), in: document,
            context: .init(activePageID: pageID, currentSceneID: sceneID, rendererGeneration: document.revision,
                selectedNodeIDs: [frame.id], availableNodeIDs: [frame.id], isLifecycleAvailable: true, lifecycleDisabledReason: nil))
        try session.execute(prepared.command)
        let definition = try XCTUnwrap(session.document.componentDefinitions.first)
        let source = try XCTUnwrap(definition.nodes.first { $0.kind == .text })
        func textEdit(_ edit: ComponentEdit, page: PageID, selected: NodeID) throws {
            let change = try ComponentCommandRegistry().prepare(edit, identity: .init(documentID: document.id,
                pageID: page, revision: session.document.revision, sceneID: sceneID,
                rendererGeneration: session.document.revision), in: session.document,
                context: .init(activePageID: page, currentSceneID: sceneID, rendererGeneration: session.document.revision,
                    selectedNodeIDs: [selected], availableNodeIDs: [selected], isLifecycleAvailable: true, lifecycleDisabledReason: nil))
            try session.execute(change.command)
        }
        try textEdit(.exposeText(nodeID: source.id, label: "Caption", defaultValue: "Default caption"), page: definition.id, selected: source.id)
        let binding = try XCTUnwrap(CanonicalComponentText.properties(in: session.document.componentDefinitions[0]).first)
        try textEdit(.setTextOverride(instanceID: frame.id, propertyID: binding.id, value: "Saved caption"), page: pageID, selected: frame.id)
        let duplicate = try PageCommandRegistry().prepare(.duplicate, identity: .init(documentID: document.id,
            revision: session.document.revision, pageID: pageID), in: session.document, isAvailable: true)
        try session.execute(duplicate.command)
        XCTAssertEqual(session.document.componentDefinitions.count, 1)
        let instances = session.document.websitePages.flatMap(\.nodes).filter { $0.kind == .component }
        XCTAssertEqual(instances.count, 2)
        XCTAssertTrue(instances.allSatisfy { CanonicalComponentText.overrides(on: $0)[binding.id] == "Saved caption" })
        XCTAssertEqual(Set(instances.compactMap { CanonicalComponentReference.definitionID(for: $0) }).count, 1)
        let package = try ProjectPackage(document: session.document).withResource(descriptor, data: bytes)
        let backend = DocumentLifecycleBackend()
        let destination = fixture.url.appendingPathComponent("Components.siteforge")
        func identity(_ url: URL, _ kind: LifecycleDestinationKind, _ intent: LifecycleOperationIntent) -> LifecycleOperationIdentity {
            .init(id: LifecycleOperationID(), epoch: LifecycleEpoch(), documentID: document.id,
                projectID: package.projectID, revision: session.document.revision,
                destination: .file(url, kind: kind), intent: intent)
        }
        _ = try await backend.write(package, history: session.historySnapshot(), to: destination, expected: nil,
            identity: identity(destination, .durable, .saveAs))
        let reopened = try await backend.read(from: destination, identity: identity(destination, .durable, .open))
        XCTAssertEqual(reopened.package.document, session.document)
        XCTAssertEqual(try reopened.package.resourceData(for: descriptor), bytes)
        let recoveryDirectory = fixture.url.appendingPathComponent("recovery", isDirectory: true)
        let store = ProjectPackageStore()
        try await store.prepareRecoveryDirectory(recoveryDirectory)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(for: package.projectID, in: recoveryDirectory)
        _ = try await backend.write(package, history: session.historySnapshot(), to: recoveryURL, expected: nil,
            identity: identity(recoveryURL, .recovery, .autosave))
        let recovered = try await backend.read(from: recoveryURL, identity: identity(recoveryURL, .recovery, .restore))
        XCTAssertEqual(recovered.package.document, session.document)
        XCTAssertEqual(try recovered.package.resourceData(for: descriptor), bytes)
        for page in recovered.package.document.websitePages {
            let resolved = try ComponentGraphResolver.resolvedPage(page, in: recovered.package.document, breakpoint: .mobile)
            for node in resolved.nodes where node.kind == .image {
                XCTAssertEqual(node.insertionStringProperty("content.image.v1.assetID"), asset.id.description)
            }
            for node in resolved.nodes where node.kind == .text {
                XCTAssertEqual(node.insertionStringProperty("content.text"), "Saved caption")
            }
        }
    }

    private var fixtures: [ApplicationOwnedTestFixture] = []

    override func tearDownWithError() throws {
        for fixture in fixtures.reversed() { try fixture.cleanup() }
        fixtures.removeAll()
        try super.tearDownWithError()
    }

    func testRepresentativeFiveHundredAssetIndexIsDeterministicAndExceedsInlinePackageCapacity() async throws {
        let fixture = try makeFixture()
        let store = ProjectResourceStore(root: fixture.url.appendingPathComponent("Project.siteforge.resources-v1"))
        var descriptors: [ProjectResourceDescriptor] = []
        var totalBytes = 0

        for index in 0..<500 {
            let bytes = representativeAsset(index: index)
            totalBytes += bytes.count
            let id = try XCTUnwrap(ResourceID(uuidString: String(format: "50000000-0000-0000-0000-%012d", index + 1)))
            descriptors.append(try await store.put(
                id: id,
                filename: "asset-\(index).png",
                mediaType: "image/png",
                data: bytes
            ))
        }

        XCTAssertGreaterThan(totalBytes, ProjectPackageStore.maximumPackageBytes)
        let index = ProjectResourceIndex(resources: descriptors.reversed())
        try await store.validate(index)
        XCTAssertEqual(index.resources.count, 500)
        XCTAssertEqual(index.resources.map(\.id.description), index.resources.map(\.id.description).sorted())

        let package = try ProjectPackage(document: ProjectCreation.blank()).withResourceIndex(index)
        let packageBytes = try await ProjectPackageStore().encode(package)
        XCTAssertLessThan(packageBytes.count, ProjectPackageStore.maximumPackageBytes)
        let reopened = try await ProjectPackageStore().decode(packageBytes)
        XCTAssertEqual(try ProjectResourceIndex.decode(from: reopened), index)
        let reopenedAsset = try await store.data(for: index.resources[237])
        XCTAssertEqual(reopenedAsset, representativeAsset(index: 237))
    }

    func testResourceIndexRejectsDuplicateMalformedOversizedAndUnsupportedMetadata() throws {
        let valid = descriptor(id: "50000000-0000-0000-0000-000000000001", bytes: Data([1]))
        XCTAssertThrowsError(try ProjectResourceIndex(resources: [valid, valid]).validate()) {
            XCTAssertEqual($0 as? ProjectResourceError, .duplicateResource)
        }
        let malformed = ProjectResourceDescriptor(
            id: ResourceID(), filename: "../escape", mediaType: "image/png", byteCount: 1, sha256: String(repeating: "0", count: 64)
        )
        XCTAssertThrowsError(try ProjectResourceIndex(resources: [malformed]).validate())
        let oversized = ProjectResourceDescriptor(
            id: ResourceID(), filename: "large.bin", mediaType: "application/octet-stream",
            byteCount: ProjectResourceIndex.maximumResourceBytes + 1, sha256: String(repeating: "0", count: 64)
        )
        XCTAssertThrowsError(try ProjectResourceIndex(resources: [oversized]).validate())
        XCTAssertThrowsError(try ProjectResourceIndex(version: 2, resources: []).validate()) {
            XCTAssertEqual($0 as? ProjectResourceError, .unsupportedIndexVersion(2))
        }
        XCTAssertNil(try ProjectResourceIndex.decode(from: ProjectPackage(document: ProjectCreation.blank())))
    }

    func testResourceIndexRejectsUnknownFieldsAndIncorrectPackageRole() throws {
        let resource = descriptor(id: "50000000-0000-0000-0000-000000000001", bytes: Data([1]))
        let index = ProjectResourceIndex(resources: [resource])
        let encoded = try JSONEncoder().encode(index)

        var indexObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        indexObject["futureField"] = true
        let unknownIndex = try JSONSerialization.data(withJSONObject: indexObject)
        let unknownIndexPackage = ProjectPackage(
            document: ProjectCreation.blank(),
            optionalMembers: [.init(
                path: ProjectResourceIndex.packageMemberPath,
                role: .resource,
                data: unknownIndex
            )]
        )
        XCTAssertThrowsError(try ProjectResourceIndex.decode(from: unknownIndexPackage)) {
            XCTAssertEqual($0 as? ProjectResourceError, .corruptIndex)
        }

        var descriptorObject = try XCTUnwrap(
            (indexObject["resources"] as? [[String: Any]])?.first
        )
        descriptorObject["futureField"] = "unapproved"
        indexObject.removeValue(forKey: "futureField")
        indexObject["resources"] = [descriptorObject]
        let unknownDescriptor = try JSONSerialization.data(withJSONObject: indexObject)
        let unknownDescriptorPackage = ProjectPackage(
            document: ProjectCreation.blank(),
            optionalMembers: [.init(
                path: ProjectResourceIndex.packageMemberPath,
                role: .resource,
                data: unknownDescriptor
            )]
        )
        XCTAssertThrowsError(try ProjectResourceIndex.decode(from: unknownDescriptorPackage)) {
            XCTAssertEqual($0 as? ProjectResourceError, .corruptIndex)
        }

        let wrongRolePackage = ProjectPackage(
            document: ProjectCreation.blank(),
            optionalMembers: [.init(
                path: ProjectResourceIndex.packageMemberPath,
                role: .optional,
                data: encoded
            )]
        )
        XCTAssertThrowsError(try ProjectResourceIndex.decode(from: wrongRolePackage)) {
            XCTAssertEqual($0 as? ProjectResourceError, .corruptIndex)
        }
    }

    func testMissingAndCorruptResourcesAreRejectedWithoutChangingPackageBytes() async throws {
        let fixture = try makeFixture()
        let root = fixture.url.appendingPathComponent("Resources")
        let store = ProjectResourceStore(root: root)
        let bytes = representativeAsset(index: 1)
        let resource = try await store.put(filename: "hero.png", mediaType: "image/png", data: bytes)
        let index = ProjectResourceIndex(resources: [resource])
        let package = try ProjectPackage(document: ProjectCreation.blank()).withResourceIndex(index)
        let packageStore = ProjectPackageStore()
        let packageBytes = try await packageStore.encode(package)

        try FileManager.default.removeItem(at: root.appendingPathComponent("\(resource.sha256).blob"))
        await XCTAssertThrowsErrorAsync(try await store.validate(index), equals: .missingBlob)
        let unchangedPackageBytes = try await packageStore.encode(package)
        XCTAssertEqual(packageBytes, unchangedPackageBytes, "resource failures must not mutate canonical package bytes")

        _ = try await store.put(id: resource.id, filename: resource.filename, mediaType: resource.mediaType, data: bytes)
        try Data(repeating: 0xff, count: bytes.count).write(to: root.appendingPathComponent("\(resource.sha256).blob"))
        await XCTAssertThrowsErrorAsync(try await store.validate(index), equals: .corruptBlob)
    }

    func testResourceValidationCancellationIsCooperativeAndStateNeutral() async throws {
        let fixture = try makeFixture()
        let base = ProjectResourceStore(root: fixture.url.appendingPathComponent("Resources"))
        let resource = try await base.put(filename: "asset.bin", mediaType: "application/octet-stream", data: representativeAsset(index: 4))
        let barrier = ResourceCancellationBarrier(blockAt: 2)
        let store = ProjectResourceStore(
            root: fixture.url.appendingPathComponent("Resources"),
            cancellation: CooperativeCancellationCheckpoint { try barrier.check() }
        )
        let task = Task { try await store.validate(ProjectResourceIndex(resources: [resource])) }
        await barrier.waitUntilBlocked()
        task.cancel()
        barrier.release()
        do {
            try await task.value
            XCTFail("cancelled validation must not succeed")
        } catch is CancellationError {}
        let unchanged = try await base.data(for: resource)
        XCTAssertEqual(unchanged, representativeAsset(index: 4))
    }

    func testResourceStoreRequiresRestrictiveDirectoryFileAndLinkMetadata() async throws {
        let fixture = try makeFixture()
        let root = fixture.url.appendingPathComponent("Resources")
        let store = ProjectResourceStore(root: root)
        let resource = try await store.put(
            filename: "secure.bin", mediaType: "application/octet-stream", data: representativeAsset(index: 5)
        )
        let blob = root.appendingPathComponent("\(resource.sha256).blob")
        XCTAssertEqual(try permissions(at: root), 0o700)
        XCTAssertEqual(try permissions(at: blob), 0o600)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: blob.path)
        await XCTAssertThrowsErrorAsync(
            try await store.validate(ProjectResourceIndex(resources: [resource])), equals: .unsafeStore
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: blob.path)

        let alias = root.appendingPathComponent("linked.blob")
        try FileManager.default.linkItem(at: blob, to: alias)
        await XCTAssertThrowsErrorAsync(
            try await store.validate(ProjectResourceIndex(resources: [resource])), equals: .unsafeStore
        )
        try FileManager.default.removeItem(at: alias)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        await XCTAssertThrowsErrorAsync(
            try await store.validate(ProjectResourceIndex(resources: [resource])), equals: .unsafeStore
        )
    }

    func testResourceStoreRejectsExtendedACLsOnRootAndBlob() async throws {
        let fixture = try makeFixture()
        let root = fixture.url.appendingPathComponent("Resources")
        let store = ProjectResourceStore(root: root)
        let resource = try await store.put(
            filename: "private.bin",
            mediaType: "application/octet-stream",
            data: representativeAsset(index: 6)
        )
        let index = ProjectResourceIndex(resources: [resource])
        let blob = root.appendingPathComponent("\(resource.sha256).blob")

        try run("/bin/chmod", arguments: ["+a", "everyone allow search", root.path])
        await XCTAssertThrowsErrorAsync(try await store.validate(index), equals: .unsafeStore)
        try run("/bin/chmod", arguments: ["-a", "everyone allow search", root.path])

        try run("/bin/chmod", arguments: ["+a", "everyone allow read", blob.path])
        await XCTAssertThrowsErrorAsync(try await store.validate(index), equals: .unsafeStore)
    }

    func testResourceStoreRemainsBoundToValidatedRootWhenPathIsExchanged() async throws {
        let fixture = try makeFixture()
        let root = fixture.url.appendingPathComponent("Resources")
        let displaced = fixture.url.appendingPathComponent("Displaced")
        let redirected = fixture.url.appendingPathComponent("Redirected")
        let originalBytes = representativeAsset(index: 7)
        let base = ProjectResourceStore(root: root)
        let resource = try await base.put(
            filename: "original.bin",
            mediaType: "application/octet-stream",
            data: originalBytes
        )

        try FileManager.default.createDirectory(at: redirected, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: redirected.path)
        let redirectedBlob = redirected.appendingPathComponent("\(resource.sha256).blob")
        try Data(repeating: 0xff, count: originalBytes.count).write(to: redirectedBlob)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: redirectedBlob.path)

        let barrier = ResourceStoreDescriptorBarrier()
        let guarded = ProjectResourceStore(
            root: root,
            ioObserver: ProjectResourceIOObserver { phase in
                if case .storeDescriptorBound = phase { barrier.reachAndWait() }
            }
        )
        let read = Task { try await guarded.data(for: resource) }
        await barrier.waitUntilReached()
        try FileManager.default.moveItem(at: root, to: displaced)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: redirected)
        barrier.release()

        let readBytes = try await read.value
        XCTAssertEqual(readBytes, originalBytes)
        XCTAssertEqual(try Data(contentsOf: redirectedBlob), Data(repeating: 0xff, count: originalBytes.count))
    }

    func testResourceIndexSurvivesRecoveryPackageRoundTrip() async throws {
        let fixture = try makeFixture()
        let projectURL = fixture.url.appendingPathComponent("Recovered.siteforge")
        let store = ProjectResourceStore(root: ProjectResourceStore.sidecarURL(for: projectURL))
        let resource = try await store.put(filename: "recovered.jpg", mediaType: "image/jpeg", data: representativeAsset(index: 9))
        let index = ProjectResourceIndex(resources: [resource])
        let package = try ProjectPackage(document: ProjectCreation.blank()).withResourceIndex(index)
        let packageStore = ProjectPackageStore()
        try await packageStore.write(package, to: projectURL)
        let recovered = try await packageStore.read(from: projectURL)
        XCTAssertEqual(try ProjectResourceIndex.decode(from: recovered), index)
        try await store.validate(index)
    }

    func testRepositoryFixtureAllocatorIsUniqueContainedAndResidueFree() throws {
        let first = try RepositoryTestFixture.create("cleanup")
        let second = try RepositoryTestFixture.create("cleanup")
        XCTAssertNotEqual(first.url, second.url)
        XCTAssertTrue(first.url.path.hasPrefix(RepositoryTestFixture.root.path + "/"))
        XCTAssertTrue(RepositoryTestFixture.root.path.hasPrefix(ApplicationOwnedTestFixture.root.path + "/"))
        try Data("fixture".utf8).write(to: first.url.appendingPathComponent("nested.txt"))
        try first.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
        try second.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.url.path))

        let outside = RepositoryTestFixture(url: FileManager.default.temporaryDirectory)
        XCTAssertThrowsError(try outside.cleanup())
    }

    // SF-0801-001...008 — import performs native raster validation away
    // from the document actor, retains exact bytes, and never stores a path.
    // SF-1207-004/005, existing SF-0801 resource ownership; source only, unrun.
    @MainActor
    func testSiteFaviconUsesTrackedResourceAndKeepsOriginalBytesAcrossMetadataUndo() async throws {
        let fixture = try makeFixture()
        let original = try makePNG(width: 8, height: 8)
        let store = ProjectResourceStore(root: fixture.url.appendingPathComponent("Favicon.resources-v1"))
        let descriptor = try await store.put(id: ResourceID(), filename: "icon.png", mediaType: "image/png", data: original)
        let asset = ImageAsset(resourceID: descriptor.id, displayName: "Icon", originalFilename: "icon.png",
            format: .png, pixelWidth: 8, pixelHeight: 8, byteCount: original.count, contentHash: ProjectResourceStore.digest(original))
        var document = ProjectCreation.blank()
        document.imageAssets = [asset]
        let session = DocumentSession(document: document)
        try session.execute(.setWebsiteMetadata(.init(documentID: document.id,
            metadata: .init(siteName: "Studio", faviconAssetID: asset.id))))
        XCTAssertEqual(ImageAssetReference.references(to: asset.id, in: session.document).map(\.kind), [.favicon])
        XCTAssertThrowsError(try session.execute(.removeImageAsset(.init(assetID: asset.id))))
        let plan = StaticBuildCompiler.compile(document: session.document, profileSelection: .init(profile: .development),
            resourceDescriptors: [descriptor.id: descriptor], resourceData: [descriptor.id: original])
        XCTAssertTrue(plan.canWrite)
        XCTAssertTrue(try XCTUnwrap(plan.plan).binaryFiles.contains { $0.contents == original })
        let bytes = try await store.data(for: descriptor)
        XCTAssertEqual(bytes, original)
        try session.undo()
        XCTAssertTrue(ImageAssetReference.references(to: asset.id, in: session.document).isEmpty)
        try session.redo()
        XCTAssertEqual(session.document.websiteMetadata?.faviconAssetID, asset.id)
        var missing = session.document
        missing.imageAssets = []
        XCTAssertEqual(missing.websiteMetadata?.faviconAssetID, asset.id)
        let unavailable = StaticBuildCompiler.compile(document: missing, profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:])
        XCTAssertFalse(unavailable.canWrite)
        XCTAssertTrue(unavailable.findings.contains { $0.code == "favicon-missing" })
        let afterHistory = try await store.data(for: descriptor)
        XCTAssertEqual(afterHistory, original)
    }

    func testImageImportPreservesExactBytesMetadataAndRejectsCorruptInput() async throws {
        let fixture = try makeFixture()
        let imageURL = fixture.url.appendingPathComponent("Calm sample.png")
        let original = try makePNG(width: 7, height: 5)
        try original.write(to: imageURL)

        let prepared = try await ImageImportWorker().prepare(url: imageURL)
        XCTAssertEqual(prepared.data, original)
        XCTAssertEqual(prepared.asset.pixelWidth, 7)
        XCTAssertEqual(prepared.asset.pixelHeight, 5)
        XCTAssertEqual(prepared.asset.format, .png)
        XCTAssertEqual(prepared.asset.displayName, "Calm sample")
        XCTAssertEqual(prepared.asset.contentHash, ProjectResourceStore.digest(original))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(prepared.asset), as: UTF8.self).contains(fixture.url.path))
        try prepared.asset.validate()

        let corruptURL = fixture.url.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: corruptURL)
        do {
            _ = try await ImageImportWorker().prepare(url: corruptURL)
            XCTFail("corrupt raster bytes must not become an asset")
        } catch {
            XCTAssertEqual(error as? ImageImportError, .corrupt)
        }
    }

    func testImageCanonicalNamespaceAndMetadataRejectIncompleteUnknownAndOversizedValues() throws {
        func property(_ key: String, _ value: PropertyValue) -> NodeProperty {
            NodeProperty(key: PropertyKey(rawValue: CanonicalImageStyle.namespace + key), value: value, origin: .authored)
        }
        let assetID = AssetID()
        let valid: [NodeProperty] = [
            property("assetID", .string(assetID.description)),
            property("fit", .string(ImageFitMode.fit.rawValue)),
            property("focal.x", .number(0.5)),
            property("focal.y", .number(0.5)),
            property("alt", .string("Product photograph")),
            property("decorative", .boolean(false)),
        ]
        let parent = NodeParent.node(NodeID())
        XCTAssertNoThrow(try CanonicalImageNamespaceValidator.validate(
            DocumentNode(kind: .image, name: "Image", parent: parent, properties: valid)
        ))
        XCTAssertThrowsError(try CanonicalImageNamespaceValidator.validate(
            DocumentNode(kind: .image, name: "Image", parent: parent, properties: Array(valid.dropLast()))
        )) { XCTAssertEqual($0 as? ModelValidationError, .invalidImageReference) }
        XCTAssertThrowsError(try CanonicalImageNamespaceValidator.validate(
            DocumentNode(kind: .image, name: "Image", parent: parent, properties: valid + [property("unknown", .string("value"))])
        )) { XCTAssertEqual($0 as? ModelValidationError, .invalidImageReference) }
        XCTAssertThrowsError(try CanonicalImageNamespaceValidator.validate(
            DocumentNode(kind: .frame, name: "Frame", parent: parent, properties: valid)
        )) { XCTAssertEqual($0 as? ModelValidationError, .invalidImageReference) }

        let oversizedFilename = String(repeating: "a", count: ImageAsset.maximumOriginalFilenameBytes + 1)
        let asset = ImageAsset(
            resourceID: ResourceID(), displayName: "Image", originalFilename: oversizedFilename,
            format: .png, pixelWidth: 1, pixelHeight: 1, byteCount: 1,
            contentHash: String(repeating: "0", count: 64)
        )
        XCTAssertThrowsError(try asset.validate()) {
            XCTAssertEqual($0 as? ModelValidationError, .invalidImageAsset)
        }
    }

    // SF-0801-001, SF-0801-004, SF-0802-004 — canonical index remains in
    // the bounded package while original bytes use the existing sidecar.
    func testImageResourceSidecarRoundTripPreservesBytesAndMissingIntent() async throws {
        let fixture = try makeFixture()
        let projectURL = fixture.url.appendingPathComponent("Images.siteforge")
        let original = try makePNG(width: 4, height: 3)
        let hash = ProjectResourceStore.digest(original)
        let descriptor = ProjectResourceDescriptor(
            id: ResourceID(), filename: "hero.png", mediaType: "image/png",
            byteCount: original.count, sha256: hash
        )
        let asset = ImageAsset(
            resourceID: descriptor.id, displayName: "Hero", originalFilename: "hero.png",
            format: .png, pixelWidth: 4, pixelHeight: 3,
            byteCount: original.count, contentHash: hash
        )
        var document = ProjectCreation.blank()
        document.imageAssets = [asset]
        let transient = try ProjectPackage(document: document).withResource(descriptor, data: original)
        let backend = DocumentLifecycleBackend()
        let identity = LifecycleOperationIdentity(
            id: LifecycleOperationID(), epoch: LifecycleEpoch(),
            documentID: document.id, projectID: transient.projectID,
            revision: document.revision,
            destination: .file(projectURL, kind: .durable), intent: .saveAs
        )
        let history = PersistedHistorySnapshot(
            documentID: document.id, documentRevision: document.revision,
            boundaryRevision: document.revision, undoEntries: [], redoEntries: []
        )
        let completed = try await backend.write(
            transient, history: history,
            to: projectURL, expected: nil, identity: identity
        )
        XCTAssertEqual(completed.destinationURL, projectURL)
        let packageBytes = try Data(contentsOf: projectURL)
        XCTAssertFalse(packageBytes.range(of: original) != nil, "resource bytes must not be embedded in the package")
        let sidecar = ProjectResourceStore(root: ProjectResourceStore.sidecarURL(for: projectURL))
        let persistedBytes = try await sidecar.data(for: descriptor)
        XCTAssertEqual(persistedBytes, original)

        let readIdentity = LifecycleOperationIdentity(
            id: LifecycleOperationID(), epoch: LifecycleEpoch(),
            documentID: document.id, projectID: transient.projectID,
            revision: document.revision,
            destination: .file(projectURL, kind: .durable), intent: .open
        )
        let reopened = try await backend.read(from: projectURL, identity: readIdentity)
        XCTAssertEqual(try reopened.package.resourceData(for: descriptor), original)
        XCTAssertEqual(reopened.package.document.imageAssets, [asset])

        try FileManager.default.removeItem(at: ProjectResourceStore.sidecarURL(for: projectURL))
        let missing = try await backend.read(from: projectURL, identity: readIdentity)
        XCTAssertEqual(missing.package.document.imageAssets, [asset], "missing bytes retain authored AssetID intent")
        XCTAssertThrowsError(try missing.package.resourceData(for: descriptor)) {
            XCTAssertEqual($0 as? ProjectResourceError, .missingBlob)
        }
    }

    @MainActor
    func testRejectedAssetMutationRollsBackStagedResourceBytes() throws {
        let fixture = try makeFixture()
        let controller = DocumentLifecycleController(
            session: DocumentSession(),
            recoveryDirectory: fixture.url.appendingPathComponent("recovery", isDirectory: true)
        )
        let bytes = try makePNG(width: 2, height: 2)
        let descriptor = ProjectResourceDescriptor(
            id: ResourceID(), filename: "rollback.png", mediaType: "image/png",
            byteCount: bytes.count, sha256: ProjectResourceStore.digest(bytes)
        )
        enum Expected: Error { case rejected }
        XCTAssertThrowsError(try controller.installingProjectResource(descriptor, data: bytes) {
            throw Expected.rejected
        }) { XCTAssertTrue($0 is Expected) }
        XCTAssertThrowsError(try controller.projectResourceData(for: descriptor.id)) {
            XCTAssertEqual($0 as? ProjectResourceError, .missingBlob)
        }

        let result: String = try controller.installingProjectResource(descriptor, data: bytes) { "committed" }
        XCTAssertEqual(result, "committed")
        XCTAssertEqual(try controller.projectResourceData(for: descriptor.id), bytes)
    }

    @MainActor
    func testImageAssetRenameAndReplacementPreserveIdentityWithExactUndoRedo() throws {
        let firstBytes = try makePNG(width: 3, height: 2)
        let secondBytes = try makePNG(width: 5, height: 4)
        let stableID = AssetID()
        let original = ImageAsset(
            id: stableID, resourceID: ResourceID(), displayName: "Hero",
            originalFilename: "hero.png", format: .png, pixelWidth: 3, pixelHeight: 2,
            byteCount: firstBytes.count, contentHash: ProjectResourceStore.digest(firstBytes)
        )
        let session = DocumentSession()
        try session.execute(.insertImageAsset(.init(asset: original, index: 0)))

        var renamed = original
        renamed.displayName = "Primary hero"
        try session.execute(.updateImageAsset(.init(asset: renamed)))
        XCTAssertEqual(session.document.imageAssets[0].id, stableID)
        XCTAssertEqual(session.document.imageAssets[0].displayName, "Primary hero")

        var replaced = renamed
        replaced.resourceID = ResourceID()
        replaced.originalFilename = "replacement.png"
        replaced.pixelWidth = 5; replaced.pixelHeight = 4
        replaced.byteCount = secondBytes.count
        replaced.contentHash = ProjectResourceStore.digest(secondBytes)
        try session.execute(.updateImageAsset(.init(asset: replaced)))
        XCTAssertEqual(session.document.imageAssets, [replaced])
        try session.undo()
        XCTAssertEqual(session.document.imageAssets, [renamed])
        try session.undo()
        XCTAssertEqual(session.document.imageAssets, [original])
        try session.redo(); try session.redo()
        XCTAssertEqual(session.document.imageAssets, [replaced])

        let duplicate = ImageAsset(
            resourceID: ResourceID(), displayName: "Duplicate",
            originalFilename: "duplicate.png", format: replaced.format,
            pixelWidth: replaced.pixelWidth, pixelHeight: replaced.pixelHeight,
            byteCount: replaced.byteCount, contentHash: replaced.contentHash
        )
        let duplicateCommand = DocumentCommand.insertImageAsset(.init(asset: duplicate, index: 1))
        XCTAssertFalse(CommandRegistry().availability(for: duplicateCommand, in: session.document).isEnabled)
    }

    // SF-0801-004, SF-0802-001...008 — asset/node insertion and Image
    // Inspector edits use exact command inverses and preserve stable IDs.
    @MainActor
    func testImageAssetInsertionInspectorUndoRedoAndSchemaMigration() throws {
        var document = ProjectCreation.blank()
        let bytes = try makePNG(width: 9, height: 6)
        let hash = ProjectResourceStore.digest(bytes)
        let asset = ImageAsset(
            resourceID: ResourceID(), displayName: "Product", originalFilename: "product.png",
            format: .png, pixelWidth: 9, pixelHeight: 6,
            byteCount: bytes.count, contentHash: hash
        )
        let session = DocumentSession(document: document)
        try session.execute(.insertImageAsset(.init(asset: asset, index: 0)))
        let pageID = document.pages[0].id
        let rootID = document.pages[0].rootNodeIDs[0]
        let nodeID = NodeID()
        let sceneID = CanvasViewportSceneID()
        let command = AuthoringInsertionCommand.image(.init(
            identity: .init(documentID: session.document.id, pageID: pageID, revision: session.document.revision, generation: 1),
            nodeID: nodeID, parentID: rootID, index: 0,
            geometry: .defaultValue(for: .image, at: .init(x: 80, y: 90)),
            assetID: asset.id, provenance: .menu
        ))
        let prepared = try InsertionCommandRegistry().prepare(command, in: session.document, context: .init(
            activePageID: pageID, activeRoute: .init(rawValue: "/"), operationGeneration: 1,
            availableNodeIDs: Set(session.document.pages[0].nodes.map(\.id))
        ))
        try session.execute(prepared.documentCommand)
        let inserted = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == nodeID })
        XCTAssertEqual(inserted.kind, .image)
        XCTAssertEqual(CanonicalImageStyle.resolve(inserted)?.assetID, asset.id)

        let context = TransformValidationContext(
            activePageID: pageID, currentSceneID: sceneID, rendererGeneration: 7,
            selectedNodeIDs: [nodeID], availableNodeIDs: [nodeID],
            isLifecycleAvailable: true, lifecycleDisabledReason: nil
        )
        let identity = ImageInspectorOperationIdentity(
            documentID: session.document.id, pageID: pageID, revision: session.document.revision,
            sceneID: sceneID, rendererGeneration: 7, selectedNodeIDs: [nodeID]
        )
        let edit = try ImageInspectorCommandRegistry().prepare(
            .init(identity: identity, edit: .focal(x: 0.2, y: 0.8)),
            in: session.document, context: context
        )
        try session.execute(edit.command)
        XCTAssertEqual(CanonicalImageStyle.resolve(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == nodeID }))?.focalX, 0.2)
        try session.undo()
        XCTAssertEqual(CanonicalImageStyle.resolve(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == nodeID }))?.focalX, 0.5)
        try session.redo()
        XCTAssertEqual(CanonicalImageStyle.resolve(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == nodeID }))?.focalY, 0.8)

        XCTAssertFalse(CommandRegistry().availability(
            for: .removeImageAsset(.init(assetID: asset.id)), in: session.document
        ).isEnabled, "an in-use asset requires explicit detach resolution")
        let roundTrip = try DocumentSerializer.decode(DocumentSerializer.encode(session.document))
        XCTAssertEqual(roundTrip.imageAssets, [asset])
        XCTAssertEqual(roundTrip.pages[0].nodes.first { $0.id == nodeID }?.id, nodeID)

        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(ProjectCreation.blank())) as? [String: Any])
        legacyObject["schemaVersion"] = 4
        var legacyDocument = try XCTUnwrap(legacyObject["document"] as? [String: Any])
        legacyDocument.removeValue(forKey: "imageAssets")
        legacyDocument.removeValue(forKey: "colorTokens")
        legacyDocument.removeValue(forKey: "websiteMetadata")
        legacyObject["document"] = legacyDocument
        let migrated = try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: legacyObject))
        XCTAssertTrue(migrated.imageAssets.isEmpty)
        XCTAssertTrue(String(decoding: try DocumentSerializer.encode(migrated), as: UTF8.self).contains("\"schemaVersion\":\(DocumentSerializer.currentSchemaVersion)"))
    }

    func testImageInspectorRejectsInvalidStaleAndInapplicableEditsWithoutMutation() throws {
        let document = ProjectCreation.blank()
        let pageID = document.pages[0].id
        let nodeID = document.pages[0].rootNodeIDs[0]
        let sceneID = CanvasViewportSceneID()
        let context = TransformValidationContext(
            activePageID: pageID, currentSceneID: sceneID, rendererGeneration: 4,
            selectedNodeIDs: [nodeID], availableNodeIDs: [nodeID],
            isLifecycleAvailable: true, lifecycleDisabledReason: nil
        )
        let identity = ImageInspectorOperationIdentity(
            documentID: document.id, pageID: pageID, revision: document.revision,
            sceneID: sceneID, rendererGeneration: 4, selectedNodeIDs: [nodeID]
        )
        let registry = ImageInspectorCommandRegistry()
        XCTAssertThrowsError(try registry.prepare(
            .init(identity: identity, edit: .focal(x: .nan, y: 0.5)), in: document, context: context
        )) { XCTAssertEqual($0 as? ImageInspectorError, .invalidFocalPoint) }
        XCTAssertThrowsError(try registry.prepare(
            .init(identity: identity, edit: .fit(.fill)), in: document, context: context, cancelled: true
        )) { XCTAssertEqual($0 as? ImageInspectorError, .cancelled) }
        let stale = ImageInspectorOperationIdentity(
            documentID: document.id, pageID: pageID, revision: document.revision + 1,
            sceneID: sceneID, rendererGeneration: 4, selectedNodeIDs: [nodeID]
        )
        XCTAssertThrowsError(try registry.prepare(
            .init(identity: stale, edit: .fit(.fill)), in: document, context: context
        )) { XCTAssertEqual($0 as? ImageInspectorError, .staleRevision) }
        XCTAssertThrowsError(try registry.prepare(
            .init(identity: identity, edit: .fit(.fill)), in: document, context: context
        )) { XCTAssertEqual($0 as? ImageInspectorError, .noApplicableTarget) }
    }

    func testImageThumbnailIsBoundedDerivativeWithoutChangingOriginalBytes() async throws {
        let original = try makePNG(width: 640, height: 360)
        let thumbnail = try await ImageThumbnailWorker().thumbnailPNG(from: original, maximumPixelSize: 80)
        XCTAssertNotEqual(thumbnail, original)
        XCTAssertEqual(ProjectResourceStore.digest(original), ProjectResourceStore.digest(original))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertLessThanOrEqual(try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int), 80)
        XCTAssertLessThanOrEqual(try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int), 80)
    }

    @MainActor
    func testExplicitInUseAssetResolutionIsOneExactUndoableBatch() throws {
        let bytes = try makePNG(width: 16, height: 9)
        let asset = ImageAsset(
            resourceID: ResourceID(), displayName: "Hero", originalFilename: "hero.png",
            format: .png, pixelWidth: 16, pixelHeight: 9,
            byteCount: bytes.count, contentHash: ProjectResourceStore.digest(bytes)
        )
        let session = DocumentSession()
        try session.execute(.insertImageAsset(.init(asset: asset, index: 0)))
        let page = session.document.pages[0]
        let rootID = page.rootNodeIDs[0]
        func property(_ key: String, _ value: PropertyValue, _ origin: PropertyOrigin) -> NodeProperty {
            NodeProperty(id: PropertyID(), key: PropertyKey(rawValue: key), value: value, origin: origin)
        }
        let node = DocumentNode(
            kind: .image, name: "Image", parent: .node(rootID), childIDs: [], properties: [
                property("layout.x", .number(20), .authored),
                property("layout.y", .number(20), .authored),
                property("layout.width", .number(320), .authored),
                property("layout.height", .number(240), .authored),
                property(CanonicalImageStyle.namespace + "assetID", .string(asset.id.description), .authored),
                property(CanonicalImageStyle.namespace + "fit", .string(ImageFitMode.fit.rawValue), .defaulted),
                property(CanonicalImageStyle.namespace + "focal.x", .number(0.5), .defaulted),
                property(CanonicalImageStyle.namespace + "focal.y", .number(0.5), .defaulted),
                property(CanonicalImageStyle.namespace + "alt", .string(""), .defaulted),
                property(CanonicalImageStyle.namespace + "decorative", .boolean(false), .defaulted),
            ]
        )
        try session.execute(.insertNode(.init(pageID: page.id, node: node, index: 0)))
        let beforeResolution = session.document
        try session.execute(.batch([
            .removeNode(.init(pageID: page.id, nodeID: node.id)),
            .removeImageAsset(.init(assetID: asset.id)),
        ]))
        XCTAssertTrue(session.document.imageAssets.isEmpty)
        XCTAssertFalse(session.document.pages[0].nodes.contains(where: { $0.id == node.id }))
        try session.undo()
        XCTAssertEqual(session.document.id, beforeResolution.id)
        XCTAssertEqual(session.document.pages, beforeResolution.pages)
        XCTAssertEqual(session.document.imageAssets, beforeResolution.imageAssets)
        XCTAssertGreaterThan(session.document.revision, beforeResolution.revision)
        try session.redo()
        XCTAssertTrue(session.document.imageAssets.isEmpty)
        XCTAssertFalse(session.document.pages[0].nodes.contains(where: { $0.id == node.id }))
    }

    // SF-0804-001/004/008 (OD-045): an SVG is stored only as a canonical,
    // sanitized re-serialization. Scripts, foreignObject, animation, external
    // references and event attributes never survive; entity declarations, a
    // non-SVG root, malformed XML and runaway nesting are refused.
    func testSVGSanitizerRemovesScriptsExternalReferencesAndEventAttributes() throws {
        let hostile = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!-- editor comment -->
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 24 12" onload="alert(1)">
          <title>  Brand
            mark </title>
          <script>alert(2)</script>
          <style>@import url(https://evil.example/x.css); .a { fill: red }</style>
          <style>.b { stroke: #00f }</style>
          <defs><path id="p" d="M0 0h4v4H0z"/></defs>
          <use xlink:href="#p" onclick="steal()"/>
          <use href="https://evil.example/sprite.svg#p"/>
          <image href="https://evil.example/tracker.png" width="1" height="1"/>
          <foreignObject><div xmlns="http://www.w3.org/1999/xhtml">x</div></foreignObject>
          <a href="javascript:alert(3)"><rect width="4" height="4" fill="url(https://evil.example/#g)" style="fill: blue; background: url(https://evil.example/b.png)"/></a>
          <circle cx="2" cy="2" r="1" fill="url(#local)" data-note="a &amp; b"/>
          <animate attributeName="href" to="javascript:alert(4)"/>
        </svg>
        """
        let sanitized = try SVGAssetSanitizer.sanitize(Data(hostile.utf8))
        let text = String(decoding: sanitized.data, as: UTF8.self)
        for forbidden in ["script", "onload", "onclick", "evil.example", "foreignObject", "animate", "javascript", "<!--", "<?xml", "@import"] {
            XCTAssertFalse(text.contains(forbidden), "Sanitized SVG still contains \(forbidden)")
        }
        XCTAssertTrue(text.hasPrefix("<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\""))
        for kept in ["xlink:href=\"#p\"", "fill=\"url(#local)\"", ".b { stroke: #00f }", "data-note=\"a &amp; b\"",
                     "style=\"fill: blue\"", "<rect height=\"4\"", "<title>  Brand"] {
            XCTAssertTrue(text.contains(kept), "Sanitized SVG lost \(kept)")
        }
        XCTAssertEqual(sanitized.report.removedElementCount, 6, "script, unsafe style, external image, foreignObject, a, animate")
        XCTAssertEqual(sanitized.report.removedAttributeCount, 5, "onload, onclick, external href ×2, external fill")
        XCTAssertEqual(sanitized.report.title, "Brand mark")
        XCTAssertEqual(sanitized.report.dimensionSource, .viewBox)
        XCTAssertEqual(sanitized.report.pixelWidth, 24); XCTAssertEqual(sanitized.report.pixelHeight, 12)
        XCTAssertEqual(sanitized.report.paintColors, ["#00f", "blue"])
        XCTAssertTrue(sanitized.report.hasComplexPaint); XCTAssertFalse(sanitized.report.isRecolorCompatible)
        // Canonical and idempotent: export can verify stored bytes exactly.
        XCTAssertEqual(try SVGAssetSanitizer.sanitize(sanitized.data).data, sanitized.data)
        XCTAssertEqual(try SVGAssetSanitizer.sanitize(Data(hostile.utf8)).data, sanitized.data)
        XCTAssertTrue(SVGAssetSanitizer.isCanonicalSanitized(sanitized.data))
        XCTAssertFalse(SVGAssetSanitizer.isCanonicalSanitized(Data(hostile.utf8)))
        let embedded = try SVGAssetSanitizer.sanitize(Data(#"<svg xmlns="http://www.w3.org/2000/svg"><image href="data:image/png;base64,AAAA" width="1" height="1"/></svg>"#.utf8))
        XCTAssertTrue(String(decoding: embedded.data, as: UTF8.self).contains("href=\"data:image/png;base64,AAAA\""))

        func failure(_ source: String) -> ImageImportError? {
            do { _ = try SVGAssetSanitizer.sanitize(Data(source.utf8)); return nil } catch { return error as? ImageImportError }
        }
        XCTAssertEqual(failure(#"<?xml version="1.0"?><!DOCTYPE svg [<!ENTITY x "boom">]><svg xmlns="http://www.w3.org/2000/svg"><text>&x;</text></svg>"#), .unsupportedSVG)
        XCTAssertEqual(failure("<html><svg/></html>"), .unsupportedSVG)
        XCTAssertEqual(failure(#"<svg xmlns="http://www.w3.org/2000/svg"><path>"#), .corrupt)
        XCTAssertEqual(failure(""), .corrupt)
        XCTAssertEqual(failure("<svg>" + String(repeating: "<g>", count: 200) + String(repeating: "</g>", count: 200) + "</svg>"), .corrupt)
        XCTAssertEqual(failure(#"<svg width="100000" height="1"/>"#), .invalidDimensions)

        // SF-0804-001: explicit, viewBox-derived and defaulted sizes are distinguished.
        let explicit = try SVGAssetSanitizer.sanitize(Data(#"<svg width="10.2px" height="4" viewBox="0 0 1 1"/>"#.utf8)).report
        XCTAssertEqual([explicit.pixelWidth, explicit.pixelHeight], [11, 4]); XCTAssertEqual(explicit.dimensionSource, .attributes)
        let derived = try SVGAssetSanitizer.sanitize(Data(#"<svg width="48" viewBox="0 0 24 12"/>"#.utf8)).report
        XCTAssertEqual([derived.pixelWidth, derived.pixelHeight], [48, 24]); XCTAssertEqual(derived.dimensionSource, .viewBox)
        let defaulted = try SVGAssetSanitizer.sanitize(Data("<svg/>".utf8)).report
        XCTAssertEqual([defaulted.pixelWidth, defaulted.pixelHeight], [300, 150]); XCTAssertEqual(defaulted.dimensionSource, .defaulted)
        XCTAssertNil(defaulted.title)

        XCTAssertTrue(SVGAssetSanitizer.looksLikeSVG(Data(" \n<svg/>".utf8)))
        XCTAssertFalse(SVGAssetSanitizer.looksLikeSVG(try makePNG(width: 2, height: 2)))
        XCTAssertFalse(SVGAssetSanitizer.looksLikeSVG(Data("<html></html>".utf8)))

        // SF-0804-003: the Image's own alt text wins; the SVG title is a fallback.
        XCTAssertEqual(SVGAssetSanitizer.accessibleName(altText: " Logo ", isDecorative: false, svgTitle: "Brand").source, .imageAltText)
        XCTAssertEqual(SVGAssetSanitizer.accessibleName(altText: " Logo ", isDecorative: false, svgTitle: "Brand").name, "Logo")
        XCTAssertEqual(SVGAssetSanitizer.accessibleName(altText: "", isDecorative: false, svgTitle: "Brand").source, .svgTitle)
        XCTAssertEqual(SVGAssetSanitizer.accessibleName(altText: "Logo", isDecorative: true, svgTitle: "Brand").source, .decorative)
        XCTAssertEqual(SVGAssetSanitizer.accessibleName(altText: "", isDecorative: false, svgTitle: nil).source, .missing)

        // SF-0804-008: diagnostics carry the requirement and counts, never content or identities.
        let assetID = AssetID()
        let summary = SVGAssetSanitizer.diagnosticSummary(sanitized.report, assetID: assetID)
        XCTAssertTrue(summary.hasPrefix("SF-0804-004 svg-sanitize asset-"))
        XCTAssertTrue(summary.contains("removed-elements=6"))
        XCTAssertFalse(summary.contains("Brand")); XCTAssertFalse(summary.contains(assetID.description))
        XCTAssertEqual(SVGAssetSanitizer.requirementIDs.count, 8)
    }

    // SF-0804-002: compatible icons (one concrete paint, no paint servers) are
    // recolored everywhere paint appears, including currentColor and style
    // declarations; incompatible icons and invalid colors are refused.
    func testSVGRecolorRewritesEveryPaintAndRefusesIncompatibleIcons() throws {
        let icon = Data(##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M0 0h16v16z" fill="#000000"/><path d="M1 1h2" stroke="currentColor" style="stroke-width: 2; fill: #000000"/></svg>"##.utf8)
        let report = try SVGAssetSanitizer.sanitize(icon).report
        XCTAssertTrue(report.isRecolorCompatible); XCTAssertEqual(report.paintColors, ["#000000"])
        let red = try SVGAssetSanitizer.recolor(icon, to: "F00")
        let text = String(decoding: red.data, as: UTF8.self)
        XCTAssertFalse(text.contains("#000000")); XCTAssertFalse(text.lowercased().contains("currentcolor"))
        for expected in ["fill=\"#ff0000\"", "stroke=\"#ff0000\"", "stroke-width: 2; fill: #ff0000"] {
            XCTAssertTrue(text.contains(expected), "Recolor missed \(expected)")
        }
        XCTAssertEqual(red.report.paintColors, ["#ff0000"])
        XCTAssertTrue(SVGAssetSanitizer.isCanonicalSanitized(red.data))
        XCTAssertEqual(try SVGAssetSanitizer.recolor(red.data, to: "#ff0000").data, red.data, "Recoloring to the same color is neutral")
        let plain = try SVGAssetSanitizer.recolor(Data(#"<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0h1"/></svg>"#.utf8), to: "#123456")
        XCTAssertEqual(String(decoding: plain.data, as: UTF8.self),
                       ##"<svg xmlns="http://www.w3.org/2000/svg" fill="#123456"><path d="M0 0h1"/></svg>"##)
        func refusal(_ source: String, color: String = "#123456") -> ImageImportError? {
            do { _ = try SVGAssetSanitizer.recolor(Data(source.utf8), to: color); return nil } catch { return error as? ImageImportError }
        }
        XCTAssertEqual(refusal(#"<svg><linearGradient id="g"><stop stop-color="red"/></linearGradient><rect fill="url(#g)"/></svg>"#), .unsupportedSVG)
        XCTAssertEqual(refusal(#"<svg><rect fill="red"/><rect fill="blue"/></svg>"#), .unsupportedSVG)
        XCTAssertEqual(refusal("<svg/>", color: "#12"), .unsupportedSVG)
        XCTAssertEqual(SVGAssetSanitizer.normalizedHexColor(" #AbC "), "#aabbcc")
        XCTAssertNil(SVGAssetSanitizer.normalizedHexColor("#ggg"))
    }

    // SF-0804-002/004/005 (OD-045): import stores the sanitized bytes as an
    // ordinary image asset; recolor is one undoable asset update whose
    // previous bytes stay in the project; save/reopen preserves both; export
    // writes a content-addressed .svg and refuses unsanitized stored bytes;
    // SVG assets need document schema 27.
    @MainActor func testSVGAssetImportRecolorUndoSaveReopenExportAndSchemaGate() async throws {
        let fixture = try makeFixture()
        let url = fixture.url.appendingPathComponent("Brand mark.svg")
        try Data(##"<svg xmlns="http://www.w3.org/2000/svg" width="32" height="16" onload="x()"><title>Brand</title><script>x()</script><path d="M0 0h32v16H0z" fill="#111111"/></svg>"##.utf8).write(to: url)
        let prepared = try await ImageImportWorker().prepare(url: url)
        XCTAssertEqual(prepared.asset.format, .svg)
        XCTAssertEqual(prepared.descriptor.mediaType, "image/svg+xml")
        XCTAssertEqual(prepared.asset.pixelWidth, 32); XCTAssertEqual(prepared.asset.pixelHeight, 16)
        XCTAssertEqual(prepared.asset.displayName, "Brand mark")
        XCTAssertEqual(prepared.svgReport?.removedPartCount, 2)
        XCTAssertEqual(prepared.asset.contentHash, ProjectResourceStore.digest(prepared.data))
        XCTAssertFalse(String(decoding: prepared.data, as: UTF8.self).contains("script"))
        try prepared.asset.validate()
        let thumbnail = try await ImageThumbnailWorker().thumbnailPNG(from: prepared.data)
        XCTAssertEqual(thumbnail, prepared.data, "SVG previews use the sanitized vector bytes")

        let session = DocumentSession(document: ProjectCreation.blank())
        let lifecycle = DocumentLifecycleController(session: session, recoveryDirectory: fixture.url.appendingPathComponent("svg-recovery"))
        _ = try lifecycle.installingProjectResource(prepared.descriptor, data: prepared.data) {
            try session.execute(.insertImageAsset(.init(asset: prepared.asset, index: 0)))
        }
        let state = WorkspaceShellState(documentSession: session, lifecycle: lifecycle)
        let imported = session.document, history = session.historySnapshot().undoEntries.count
        XCTAssertEqual(state.svgAssetReport(prepared.asset.id)?.title, "Brand")
        XCTAssertNotNil(state.svgRecolorPreview(prepared.asset.id, hex: "#2266aa"))
        XCTAssertEqual(session.document, imported, "A recolor preview must not commit")
        XCTAssertFalse(state.recolorSVGAsset(prepared.asset.id, hex: "not a color"))
        XCTAssertEqual(session.document, imported); XCTAssertEqual(session.historySnapshot().undoEntries.count, history)
        XCTAssertTrue(state.recolorSVGAsset(prepared.asset.id, hex: "#2266aa"))
        XCTAssertEqual(session.historySnapshot().undoEntries.count, history + 1)
        XCTAssertFalse(state.recolorSVGAsset(prepared.asset.id, hex: "#2266AA"), "The same color again is neutral")
        XCTAssertEqual(session.historySnapshot().undoEntries.count, history + 1)
        let recolored = try XCTUnwrap(session.document.imageAssets.first)
        XCTAssertEqual(recolored.id, prepared.asset.id)
        XCTAssertNotEqual(recolored.resourceID, prepared.asset.resourceID)
        let recoloredBytes = try lifecycle.projectResourceData(for: recolored.resourceID)
        XCTAssertTrue(String(decoding: recoloredBytes, as: UTF8.self).contains("#2266aa"))
        XCTAssertEqual(recolored.contentHash, ProjectResourceStore.digest(recoloredBytes))
        try session.undo()
        XCTAssertEqual(session.document.imageAssets, imported.imageAssets)
        XCTAssertEqual(try lifecycle.projectResourceData(for: prepared.asset.resourceID), prepared.data)
        try session.redo()
        XCTAssertEqual(session.document.imageAssets, [recolored])

        let package = fixture.url.appendingPathComponent("SVG.siteforge")
        let saved = await lifecycle.save(to: package); XCTAssertTrue(saved)
        let reader = DocumentLifecycleController(session: DocumentSession(), recoveryDirectory: fixture.url.appendingPathComponent("svg-reader-recovery"))
        let opened = await reader.requestOpen(package); XCTAssertEqual(opened, .completed)
        XCTAssertEqual(reader.session.document.imageAssets, session.document.imageAssets)
        XCTAssertEqual(try reader.projectResourceData(for: recolored.resourceID), recoloredBytes)

        let descriptor = ProjectResourceDescriptor(id: recolored.resourceID, filename: recolored.originalFilename,
            mediaType: "image/svg+xml", byteCount: recoloredBytes.count, sha256: recolored.contentHash)
        let entries = try StaticAssetExportPlanner.plan(index: .init(resources: [descriptor]), blobs: [recolored.contentHash: recoloredBytes])
        XCTAssertEqual(entries.map(\.outputPath), ["assets/\(recolored.contentHash).svg"])
        var document = session.document
        let root = document.pages[0].rootNodeIDs[0]
        let image = DocumentNode(kind: .image, name: "Logo", parent: .node(root), properties: [
            ("layout.x", PropertyValue.number(0)), ("layout.y", .number(0)), ("layout.width", .number(64)), ("layout.height", .number(32)),
            (CanonicalImageStyle.namespace + "assetID", .string(recolored.id.description)),
            (CanonicalImageStyle.namespace + "fit", .string(ImageFitMode.fit.rawValue)),
            (CanonicalImageStyle.namespace + "focal.x", .number(0.5)), (CanonicalImageStyle.namespace + "focal.y", .number(0.5)),
            (CanonicalImageStyle.namespace + "alt", .string("Brand logo")), (CanonicalImageStyle.namespace + "decorative", .boolean(false)),
        ].map { NodeProperty(key: .init(rawValue: $0.0), value: $0.1) })
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == root })
        document.pages[0].nodes[rootIndex].childIDs.append(image.id)
        document.pages[0].nodes.append(image)
        try document.validate()
        let markup = try MultiPageStaticBuildPlanner.plan(document: document, imageOutputEntries: entries)
            .files.map(\.contents).joined(separator: "\n")
        XCTAssertTrue(markup.contains("src=\"assets/\(recolored.contentHash).svg\""))
        XCTAssertTrue(markup.contains("alt=\"Brand logo\""))
        let smuggled = Data(#"<svg xmlns="http://www.w3.org/2000/svg"><script>x()</script></svg>"#.utf8)
        let smuggledDescriptor = ProjectResourceDescriptor(id: ResourceID(), filename: "x.svg", mediaType: "image/svg+xml",
            byteCount: smuggled.count, sha256: ProjectResourceStore.digest(smuggled))
        XCTAssertThrowsError(try StaticAssetExportPlanner.plan(index: .init(resources: [smuggledDescriptor]),
                                                               blobs: [smuggledDescriptor.sha256: smuggled])) {
            XCTAssertEqual($0 as? StaticAssetExportError, .corrupt)
        }

        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(session.document)) as? [String: Any])
        envelope["schemaVersion"] = 26
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: envelope)))
        var legacyDocument = try XCTUnwrap(envelope["document"] as? [String: Any])
        var legacyAssets = try XCTUnwrap(legacyDocument["imageAssets"] as? [[String: Any]])
        legacyAssets[0]["format"] = "png"
        legacyDocument["imageAssets"] = legacyAssets
        envelope["document"] = legacyDocument
        XCTAssertNoThrow(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: envelope)),
                         "Only the SVG format, not the rest of the project, needs schema 27")
    }

    // SF-0805-001/005 (OD-045): project fonts are strict, validated, omitted
    // when empty, schema-27 gated, and changed by one undoable command.
    @MainActor
    func testProjectFontModelIsStrictValidatedOmittedWhenEmptyAndUndoable() throws {
        let bytes = Data([0x00, 0x01, 0x00, 0x00] + Array(repeating: UInt8(7), count: 60))
        let font = FontAsset(resourceID: ResourceID(), family: "Brand Sans", format: .ttf, originalFilename: "brand.ttf",
                             byteCount: bytes.count, contentHash: ProjectResourceStore.digest(bytes))
        XCTAssertTrue(font.isValid); XCTAssertEqual(font.rights, .unconfirmed); XCTAssertEqual(font.fallback, .sansSerif)
        var invalid = font; invalid.family = "system"; XCTAssertFalse(invalid.isValid, "System is the reserved default family")
        invalid = font; invalid.weight = 450; XCTAssertFalse(invalid.isValid)
        invalid = font; invalid.licenseNote = "  "; XCTAssertFalse(invalid.isValid)
        invalid = font; invalid.family = " Padded"; XCTAssertFalse(invalid.isValid)
        let twin = FontAsset(resourceID: ResourceID(), family: "brand sans", format: .woff2, originalFilename: "b.woff2",
                             byteCount: 4, contentHash: String(repeating: "a", count: 64))
        XCTAssertThrowsError(try FontAsset.validate([font, twin]), "Family matching is case-insensitive")
        let italic = FontAsset(resourceID: ResourceID(), family: "brand sans", style: .italic, format: .woff2,
                               originalFilename: "b.woff2", byteCount: 4, contentHash: String(repeating: "a", count: 64))
        XCTAssertNoThrow(try FontAsset.validate([font, italic]))

        let blank = ProjectCreation.blank()
        XCTAssertFalse(String(decoding: try DocumentSerializer.encode(blank), as: UTF8.self).contains("fontAssets"))
        let session = DocumentSession(document: blank)
        try session.execute(FontAssetEditing.prepare([font], document: session.document))
        XCTAssertEqual(session.document.fontAssets, [font])
        XCTAssertThrowsError(try FontAssetEditing.prepare([font], document: session.document), "Unchanged fonts are not an edit")
        XCTAssertThrowsError(try FontAssetEditing.prepare([font, twin], document: session.document))
        let encoded = try DocumentSerializer.encode(session.document)
        XCTAssertEqual(try DocumentSerializer.decode(encoded).fontAssets, [font])
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("licenseNote"), "An absent note is omitted")
        try session.undo(); XCTAssertTrue(session.document.fontAssets.isEmpty)
        try session.redo(); XCTAssertEqual(session.document.fontAssets, [font])

        func mutated(_ change: (inout [String: Any]) -> Void) throws -> Data {
            var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            var document = try XCTUnwrap(envelope["document"] as? [String: Any])
            change(&document)
            envelope["document"] = document
            return try JSONSerialization.data(withJSONObject: envelope)
        }
        XCTAssertThrowsError(try DocumentSerializer.decode(mutated { $0["fontAssets"] = [Any]() }))
        XCTAssertThrowsError(try DocumentSerializer.decode(mutated { $0["fontAssets"] = NSNull() }))
        XCTAssertThrowsError(try DocumentSerializer.decode(mutated { document in
            guard var fonts = document["fontAssets"] as? [[String: Any]], !fonts.isEmpty else { return }
            fonts[0]["unexpected"] = 1
            document["fontAssets"] = fonts
        }))
        XCTAssertThrowsError(try DocumentSerializer.decode(mutated { document in
            guard var fonts = document["fontAssets"] as? [[String: Any]], !fonts.isEmpty else { return }
            fonts[0]["licenseNote"] = NSNull()
            document["fontAssets"] = fonts
        }))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy["schemaVersion"] = 26
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: legacy)))
    }

    // SF-0805-003: CSS Fonts 4 weight/style matching, the family fallback
    // rule, file signatures and OS/2 facts.
    func testProjectFontResolutionFollowsCSSWeightMatchingAndFallbackRule() throws {
        func face(_ weight: Int, _ style: FontFaceStyle = .normal, fallback: FontFallbackStack = .serif) -> FontAsset {
            FontAsset(resourceID: ResourceID(), family: "Brand", weight: weight, style: style, format: .woff2,
                      originalFilename: "brand-\(weight).woff2", byteCount: 4,
                      contentHash: String(repeating: "0", count: 63) + String(weight / 100), fallback: fallback)
        }
        XCTAssertEqual(ProjectFontResolver.nearestWeight(400, among: [300, 500, 700]), 500)
        XCTAssertEqual(ProjectFontResolver.nearestWeight(450, among: [300, 600]), 300)
        XCTAssertEqual(ProjectFontResolver.nearestWeight(300, among: [400, 200]), 200)
        XCTAssertEqual(ProjectFontResolver.nearestWeight(300, among: [400, 500]), 400)
        XCTAssertEqual(ProjectFontResolver.nearestWeight(600, among: [400, 800]), 800)
        XCTAssertEqual(ProjectFontResolver.nearestWeight(700, among: [400, 500]), 500)
        XCTAssertNil(ProjectFontResolver.nearestWeight(400, among: []))
        let fonts = [face(700, fallback: .monospace), face(400), face(400, .italic)]
        let exact = ProjectFontResolver.resolve(family: "brand", weight: 400, in: fonts)
        XCTAssertEqual(exact.rule, .exactFace); XCTAssertEqual(exact.face?.weight, 400); XCTAssertEqual(exact.face?.style, .normal)
        XCTAssertEqual(exact.fallback, .serif, "The family's lightest face decides its fallback")
        let nearest = ProjectFontResolver.resolve(family: "Brand", weight: 600, in: fonts)
        XCTAssertEqual(nearest.rule, .nearestFace); XCTAssertEqual(nearest.face?.weight, 700)
        let italic = ProjectFontResolver.resolve(family: "Brand", weight: 700, italic: true, in: fonts)
        XCTAssertEqual(italic.rule, .nearestFace); XCTAssertEqual(italic.face?.style, .italic); XCTAssertEqual(italic.face?.weight, 400)
        XCTAssertEqual(ProjectFontResolver.resolve(family: "Other", weight: 400, in: fonts).rule, .notProjectFont)
        XCTAssertEqual(ProjectFontResolver.families(in: fonts), ["Brand"])
        XCTAssertEqual(ProjectFontResolver.cssWeight(.semibold), 600)
        XCTAssertEqual(ProjectFontOutput.fallbackStacks(fonts: fonts)["brand"], FontFallbackStack.serif.css)
        XCTAssertEqual(ProjectFontOutput.cssFamilyName("A\"b"), "A\\22 b")

        XCTAssertEqual(ProjectFontFormatSniffer.format(of: Data([0x77, 0x4F, 0x46, 0x32, 0x00])), .woff2)
        XCTAssertEqual(ProjectFontFormatSniffer.format(of: Data("true".utf8)), .ttf)
        XCTAssertNil(ProjectFontFormatSniffer.format(of: Data("OTTO".utf8)))
        XCTAssertNil(ProjectFontFormatSniffer.format(of: Data([0x00, 0x01])))
        var os2 = [UInt8](repeating: 0, count: 96)
        os2[4] = 0x02; os2[5] = 0xBC // usWeightClass 700
        os2[9] = 0x02 // fsType: restricted license embedding
        os2[63] = 0x01 // fsSelection: italic
        XCTAssertEqual(ProjectFontMetadata.os2(Data(os2)), .init(weight: 700, italic: true, restrictedEmbedding: true))
        XCTAssertNil(ProjectFontMetadata.os2(Data(count: 10)))
    }

    // SF-0805-004/005/008: only faces declared for web embedding are
    // packaged; others, and missing or damaged files, keep the family's
    // fallback stack with a content-free warning.
    func testProjectFontsExportOnlyWithDeclaredWebRightsAndUseFallbackStacks() throws {
        let bytes = Data([0x77, 0x4F, 0x46, 0x32] + Array(repeating: UInt8(1), count: 60))
        let hash = ProjectResourceStore.digest(bytes)
        let font = FontAsset(resourceID: ResourceID(), family: "Brand Sans", weight: 400, format: .woff2,
                             originalFilename: "brand.woff2", byteCount: bytes.count, contentHash: hash, fallback: .serif)
        var document = ProjectCreation.blank()
        document.fontAssets = [font]
        let root = document.pages[0].rootNodeIDs[0]
        func text(_ weight: String, y: Double) -> DocumentNode {
            DocumentNode(kind: .text, name: "Copy", parent: .node(root), properties: [
                .init(key: .init(rawValue: "layout.x"), value: .number(0)), .init(key: .init(rawValue: "layout.y"), value: .number(y)),
                .init(key: .init(rawValue: "layout.width"), value: .number(200)), .init(key: .init(rawValue: "layout.height"), value: .number(24)),
                .init(key: .init(rawValue: "content.text"), value: .string("Hello")),
                .init(key: .init(rawValue: CanonicalTypography.namespace + "family"), value: .string("Brand Sans")),
                .init(key: .init(rawValue: CanonicalTypography.namespace + "weight"), value: .string(weight)),
                .init(key: .init(rawValue: CanonicalTypography.namespace + "size"), value: .number(18)),
                .init(key: .init(rawValue: CanonicalTypography.namespace + "lineHeight"), value: .number(24)),
                .init(key: .init(rawValue: CanonicalTypography.namespace + "tracking"), value: .number(0)),
                .init(key: .init(rawValue: CanonicalTypography.namespace + "alignment"), value: .string("leading")),
            ])
        }
        let regular = text("regular", y: 0), bold = text("bold", y: 40)
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == root })
        document.pages[0].nodes[rootIndex].childIDs += [regular.id, bold.id]
        document.pages[0].nodes += [regular, bold]
        try document.validate()
        XCTAssertEqual(ProjectFontResolver.usageCount(family: "brand sans", in: document), 2)
        let descriptor = ProjectResourceDescriptor(id: font.resourceID, filename: font.originalFilename, mediaType: "font/woff2",
                                                   byteCount: bytes.count, sha256: hash)
        func compile(_ document: CanonicalDocument, data: [ResourceID: Data]? = nil) -> StaticBuildCompilation {
            StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .development),
                resourceDescriptors: [font.resourceID: descriptor], resourceData: data ?? [font.resourceID: bytes])
        }
        func css(_ result: StaticBuildCompilation) throws -> String {
            try XCTUnwrap(result.plan?.files.first { $0.path == "styles.css" }?.contents, "\(result.findings.map(\.code))")
        }
        let fallbackDeclaration = "font-family: \"Brand Sans\", \(FontFallbackStack.serif.css);"

        let unconfirmed = compile(document)
        XCTAssertTrue(unconfirmed.findings.contains { $0.code == "font-rights-unconfirmed" })
        XCTAssertEqual(unconfirmed.plan?.binaryFiles.count, 0)
        XCTAssertFalse(try css(unconfirmed).contains("@font-face"))
        XCTAssertTrue(try css(unconfirmed).contains(fallbackDeclaration))

        document.fontAssets[0].rights = .webEmbeddingAllowed
        let allowed = compile(document)
        XCTAssertEqual(allowed.plan?.binaryFiles.map(\.path), ["assets/\(hash).woff2"])
        XCTAssertEqual(allowed.plan?.binaryFiles.first?.contents, bytes)
        // SF-1206-001 (ADR-0124): an exported face is listed in assets.manifest.txt with its media type, never its family.
        XCTAssertEqual(allowed.plan?.files.first { $0.path == "assets.manifest.txt" }?.contents,
                       "\(font.id.description)\tassets/\(hash).woff2\tfont/woff2")
        XCTAssertNil(unconfirmed.plan?.files.first { $0.path == "assets.manifest.txt" }, "A face that is not exported is not listed")
        let allowedCSS = try css(allowed)
        XCTAssertTrue(allowedCSS.contains("@font-face { font-family: \"Brand Sans\"; src: url(\"assets/\(hash).woff2\") format(\"woff2\"); font-weight: 400; font-style: normal; font-display: swap; }"), allowedCSS)
        XCTAssertTrue(allowedCSS.contains(fallbackDeclaration))
        XCTAssertTrue(allowed.findings.contains { $0.code == "font-face-missing" && $0.affectedNodeID == bold.id }, "Bold text has no 700 face")
        XCTAssertFalse(allowed.findings.contains { $0.code == "font-rights-unconfirmed" })
        XCTAssertFalse(allowed.findings.contains { $0.explanation.contains("Brand") }, "Findings carry no family names")
        let html = try XCTUnwrap(allowed.plan?.files.first { $0.path == "index.html" }?.contents)
        XCTAssertTrue(html.contains("styles.css"), "A page using a project font links the stylesheet")
        // OD-038 (ADR-0082): a page in the French tree links the same root stylesheet
        // from its folder, so the face resolves there too; the face is written once.
        var fontFrenchDocument = document
        var fontFrenchLocalization = try SiteLocalizationEditing.start(code: "en", name: "English")
        _ = try SiteLocalizationEditing.addLocale(code: "fr", name: "Français", to: &fontFrenchLocalization)
        fontFrenchDocument.localization = fontFrenchLocalization
        try fontFrenchDocument.validate()
        let fontFrenchBuild = compile(fontFrenchDocument)
        let fontFrenchHTML = try XCTUnwrap(fontFrenchBuild.plan?.files.first { $0.path == "fr/index.html" }?.contents,
                                           "\(fontFrenchBuild.findings.map(\.code))")
        XCTAssertTrue(fontFrenchHTML.contains("<link rel=\"stylesheet\" href=\"../styles.css\">"), fontFrenchHTML)
        XCTAssertEqual(fontFrenchBuild.plan?.binaryFiles.map(\.path), ["assets/\(hash).woff2"], "One face for every language")
        XCTAssertTrue(try css(fontFrenchBuild).contains("src: url(\"assets/\(hash).woff2\")"), "Relative to the root stylesheet")
        XCTAssertFalse(fontFrenchBuild.findings.contains { $0.code == "output-reference-unresolved" }, "\(fontFrenchBuild.findings.map(\.code))")

        let missing = compile(document, data: [:])
        XCTAssertTrue(missing.findings.contains { $0.code == "font-resource-missing" })
        XCTAssertEqual(missing.plan?.binaryFiles.count, 0)
        XCTAssertFalse(try css(missing).contains("@font-face"))

        let damaged = Data("<html>".utf8)
        let damagedDescriptor = ProjectResourceDescriptor(id: ResourceID(), filename: "x.woff2", mediaType: "font/woff2",
                                                          byteCount: damaged.count, sha256: ProjectResourceStore.digest(damaged))
        XCTAssertThrowsError(try StaticAssetExportPlanner.plan(index: .init(resources: [damagedDescriptor]),
                                                               blobs: [damagedDescriptor.sha256: damaged]))

        document.fontAssets[0].rights = .editorOnly
        let editorOnly = compile(document)
        XCTAssertTrue(editorOnly.findings.contains { $0.code == "font-not-licensed-for-web" })
        XCTAssertEqual(editorOnly.plan?.binaryFiles.count, 0)
    }

    // SF-0805-004: import keeps the original bytes, reads face facts and
    // never assumes web rights; unsupported and damaged files are refused.
    func testFontImportKeepsOriginalBytesAndReadsFaceFacts() async throws {
        let fixture = try makeFixture()
        let unsupported = fixture.url.appendingPathComponent("font.otf")
        try Data(Array("OTTO".utf8) + Array(repeating: UInt8(0), count: 60)).write(to: unsupported)
        do { _ = try await FontImportWorker().prepare(url: unsupported); XCTFail("OpenType-CFF is not accepted") }
        catch { XCTAssertEqual(error as? FontImportError, .unsupported) }
        let damaged = fixture.url.appendingPathComponent("broken.ttf")
        try Data([0x00, 0x01, 0x00, 0x00, 0x00]).write(to: damaged)
        do { _ = try await FontImportWorker().prepare(url: damaged); XCTFail("Damaged fonts are refused") }
        catch { XCTAssertEqual(error as? FontImportError, .corrupt) }
        let system = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Arial.ttf")
        guard FileManager.default.isReadableFile(atPath: system.path) else { throw XCTSkip("Arial.ttf is not installed on this Mac") }
        let prepared = try await FontImportWorker().prepare(url: system)
        XCTAssertEqual(prepared.font.format, .ttf); XCTAssertEqual(prepared.descriptor.mediaType, "font/ttf")
        XCTAssertEqual(prepared.font.family, "Arial"); XCTAssertEqual(prepared.font.weight, 400); XCTAssertEqual(prepared.font.style, .normal)
        XCTAssertEqual(prepared.data, try Data(contentsOf: system))
        XCTAssertEqual(prepared.font.contentHash, ProjectResourceStore.digest(prepared.data))
        XCTAssertNotEqual(prepared.font.rights, .webEmbeddingAllowed, "Rights are never assumed")
        try prepared.font.validate()
    }

    // SF-0805-002/004/005: workspace edits are one undoable step each,
    // invalid edits change nothing, removal keeps the file for Undo, and
    // fonts and their bytes survive save and reopen.
    @MainActor func testProjectFontEditsAreUndoableAndFontBytesSurviveSaveAndReopen() async throws {
        let fixture = try makeFixture()
        let bytes = Data([0x00, 0x01, 0x00, 0x00] + Array(repeating: UInt8(3), count: 60))
        let font = FontAsset(resourceID: ResourceID(), family: "Brand", format: .ttf, originalFilename: "brand.ttf",
                             byteCount: bytes.count, contentHash: ProjectResourceStore.digest(bytes))
        let descriptor = ProjectResourceDescriptor(id: font.resourceID, filename: font.originalFilename, mediaType: "font/ttf",
                                                   byteCount: bytes.count, sha256: font.contentHash)
        let session = DocumentSession(document: ProjectCreation.blank())
        let lifecycle = DocumentLifecycleController(session: session, recoveryDirectory: fixture.url.appendingPathComponent("font-recovery"))
        _ = try lifecycle.installingProjectResource(descriptor, data: bytes) {
            try session.execute(FontAssetEditing.prepare([font], document: session.document))
        }
        let state = WorkspaceShellState(documentSession: session, lifecycle: lifecycle)
        let history = session.historySnapshot().undoEntries.count
        var confirmed = font
        confirmed.rights = .webEmbeddingAllowed
        confirmed.licenseNote = "Studio web license 2026"
        XCTAssertTrue(state.updateFontAsset(confirmed))
        XCTAssertEqual(session.historySnapshot().undoEntries.count, history + 1)
        var invalid = confirmed
        invalid.weight = 350
        XCTAssertFalse(state.updateFontAsset(invalid))
        XCTAssertEqual(session.document.fontAssets, [confirmed])
        XCTAssertEqual(session.historySnapshot().undoEntries.count, history + 1)
        XCTAssertTrue(state.removeFontAsset(font.id))
        XCTAssertTrue(session.document.fontAssets.isEmpty)
        XCTAssertEqual(try lifecycle.projectResourceData(for: font.resourceID), bytes, "Removing a face keeps its file for Undo")
        try session.undo()
        XCTAssertEqual(session.document.fontAssets, [confirmed])
        let snapshot = try ProjectImageResourceSnapshot(document: session.document, package: lifecycle.staticBuildResourceSnapshot())
        XCTAssertEqual(snapshot.data[font.resourceID], bytes, "Builds receive project font bytes")
        let package = fixture.url.appendingPathComponent("Fonts.siteforge")
        let saved = await lifecycle.save(to: package); XCTAssertTrue(saved)
        let reader = DocumentLifecycleController(session: DocumentSession(), recoveryDirectory: fixture.url.appendingPathComponent("font-reader-recovery"))
        let opened = await reader.requestOpen(package); XCTAssertEqual(opened, .completed)
        XCTAssertEqual(reader.session.document.fontAssets, [confirmed])
        XCTAssertEqual(try reader.projectResourceData(for: font.resourceID), bytes)
    }

    // SF-0803-001/005 (OD-045): project video, audio and captions files are
    // strict, validated, omitted when empty, schema-27 gated, compared,
    // restored from snapshots and changed by one undoable command.
    @MainActor
    func testMediaModelIsStrictValidatedOmittedWhenEmptyAndUndoable() throws {
        let fixture = try mediaFixture()
        XCTAssertTrue(fixture.video.isValid); XCTAssertEqual(fixture.video.kind, .video)
        XCTAssertEqual(fixture.audio.format.mediaType, "audio/mpeg"); XCTAssertEqual(MediaAssetFormat.m4a.mediaType, "audio/mp4")
        var invalid = fixture.video; invalid.language = "en"; XCTAssertFalse(invalid.isValid, "Only captions carry a language")
        invalid = fixture.captions; invalid.language = "english!"; XCTAssertFalse(invalid.isValid)
        invalid = fixture.captions; invalid.language = "pt-BR"; XCTAssertTrue(invalid.isValid)
        invalid = fixture.video; invalid.displayName = "  "; XCTAssertFalse(invalid.isValid)
        invalid = fixture.video; invalid.byteCount = ImageAsset.maximumResourceBytes + 1; XCTAssertFalse(invalid.isValid)
        let twin = MediaAsset(resourceID: ResourceID(), displayName: "Twin", originalFilename: "twin.mp3", format: .mp3,
                              byteCount: 4, contentHash: fixture.audio.contentHash)
        XCTAssertThrowsError(try MediaAsset.validate([fixture.audio, twin]), "The same bytes are one file")

        let blank = ProjectCreation.blank()
        XCTAssertFalse(String(decoding: try DocumentSerializer.encode(blank), as: UTF8.self).contains("mediaAssets"))
        let session = DocumentSession(document: blank)
        try session.execute(MediaAssetEditing.prepare([fixture.video, fixture.captions], document: session.document))
        XCTAssertEqual(session.historySnapshot().undoEntries.map(\.commandName), [.setMediaAssets])
        XCTAssertThrowsError(try MediaAssetEditing.prepare([fixture.video, fixture.captions], document: session.document),
                             "Unchanged files are not an edit")
        let encoded = try DocumentSerializer.encode(session.document)
        XCTAssertEqual(try DocumentSerializer.decode(encoded).mediaAssets, [fixture.video, fixture.captions])

        func mutated(_ change: (inout [String: Any]) -> Void) throws -> Data {
            var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            var document = try XCTUnwrap(envelope["document"] as? [String: Any])
            change(&document)
            envelope["document"] = document
            return try JSONSerialization.data(withJSONObject: envelope)
        }
        var storedKeys: [Set<String>] = []
        _ = try mutated { document in
            storedKeys = ((document["mediaAssets"] as? [[String: Any]]) ?? []).map { Set($0.keys) }
        }
        XCTAssertEqual(storedKeys.map { $0.contains("language") }, [false, true], "An absent language is omitted")
        XCTAssertThrowsError(try DocumentSerializer.decode(mutated { $0["mediaAssets"] = [Any]() }))
        XCTAssertThrowsError(try DocumentSerializer.decode(mutated { $0["mediaAssets"] = NSNull() }))
        XCTAssertThrowsError(try DocumentSerializer.decode(mutated { document in
            guard var media = document["mediaAssets"] as? [[String: Any]], !media.isEmpty else { return }
            media[0]["unexpected"] = 1
            document["mediaAssets"] = media
        }))
        XCTAssertThrowsError(try DocumentSerializer.decode(mutated { document in
            guard var media = document["mediaAssets"] as? [[String: Any]], media.count > 1 else { return }
            media[1]["language"] = NSNull()
            document["mediaAssets"] = media
        }))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy["schemaVersion"] = 26
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: legacy)))

        var clash = session.document
        clash.imageAssets = [ImageAsset(id: fixture.video.id, resourceID: ResourceID(), displayName: "Clash",
            originalFilename: "clash.png", format: .png, pixelWidth: 4, pixelHeight: 4, byteCount: 4,
            contentHash: String(repeating: "b", count: 64))]
        XCTAssertThrowsError(try clash.validate(), "Media and image identities never collide")

        func source(_ document: CanonicalDocument, _ name: String) -> ProjectComparisonSource {
            ProjectComparisonSource(snapshotID: nil, name: name, document: document)
        }
        XCTAssertEqual(try ProjectComparer.compare(source(blank, "A"), with: source(session.document, "B")).changes.map(\.subject),
                       ["Video and audio files"])
        XCTAssertEqual(try ProjectSnapshots.restoreCommand(to: blank, from: session.document, resources: nil),
                       .batch([.setMediaAssets(.init(documentID: blank.id, mediaAssets: []))]))
        XCTAssertThrowsError(try ProjectSnapshots.restoreCommand(to: session.document, from: blank, resources: nil),
                             "A snapshot's files must be available to restore it")

        try session.undo(); XCTAssertTrue(session.document.mediaAssets.isEmpty)
        try session.redo(); XCTAssertEqual(session.document.mediaAssets, [fixture.video, fixture.captions])
    }

    // SF-0803-002/003/005: an Image plays a video or audio file; each change
    // is one undoable edit; omitted, defaulted and authored values stay
    // distinct; sound never starts by itself; captions are for video only.
    @MainActor
    func testMediaPlaybackRulesProvenanceAndOneUndoableEditPerChange() throws {
        let fixture = try mediaFixture()
        let session = DocumentSession(document: fixture.document)
        let pageID = fixture.document.pages[0].id
        func prepare(_ playback: CanonicalMediaPlayback?) throws -> DocumentCommand {
            try MediaPlaybackEditing.prepare(playback, nodeID: fixture.imageID, pageID: pageID, document: session.document)
        }
        func node() throws -> DocumentNode {
            try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.imageID })
        }

        XCTAssertNil(CanonicalMediaPlayback.resolve(try node()), "An Image starts without video or audio")
        let history = session.historySnapshot().undoEntries.count
        try session.execute(prepare(.init(assetID: fixture.video.id, captionsAssetID: fixture.captions.id)))
        XCTAssertEqual(session.historySnapshot().undoEntries.count, history + 1, "One undoable edit")
        var playback = try XCTUnwrap(CanonicalMediaPlayback.resolve(try node()))
        XCTAssertEqual(playback, .init(assetID: fixture.video.id, captionsAssetID: fixture.captions.id))
        XCTAssertFalse(playback.loops); XCTAssertFalse(playback.isMuted); XCTAssertFalse(playback.autoplays)
        XCTAssertEqual(playback.provenance(.loop), "Off (default)")
        XCTAssertNil(try node().insertionProperty(CanonicalMediaPlayback.Setting.loop.key), "Defaults are not written")

        XCTAssertThrowsError(try prepare(.init(assetID: fixture.video.id, autoplay: true)), "Autoplay needs muted video")
        XCTAssertThrowsError(try prepare(.init(assetID: fixture.audio.id, muted: true, autoplay: true)), "Audio never autoplays")
        XCTAssertThrowsError(try prepare(.init(assetID: fixture.audio.id, captionsAssetID: fixture.captions.id)), "Captions are for video")
        XCTAssertThrowsError(try prepare(.init(assetID: fixture.captions.id)), "Captions can't play by themselves")
        XCTAssertThrowsError(try prepare(.init(assetID: AssetID())), "The file must be in the project")
        XCTAssertThrowsError(try prepare(playback), "Unchanged settings are not an edit")

        playback.loop = false; playback.muted = true; playback.autoplay = true
        try session.execute(prepare(playback))
        let authored = try XCTUnwrap(CanonicalMediaPlayback.resolve(try node()))
        XCTAssertEqual(authored.loop, false, "An authored false stays authored")
        XCTAssertEqual(authored.provenance(.loop), "Off (set on this Image)")
        XCTAssertEqual(authored.provenance(.muted), "On (set on this Image)")
        XCTAssertTrue(authored.autoplays)
        let explanation = CanonicalMediaPlayback.explanation(authored, media: fixture.video)
        XCTAssertTrue(explanation.contains("muted autoplay"), explanation)
        XCTAssertFalse(explanation.contains(fixture.video.displayName), "No file names")
        XCTAssertEqual(MediaAssetEditing.usageCount(fixture.video.id, in: session.document), 1)
        XCTAssertEqual(MediaAssetEditing.usageCount(fixture.captions.id, in: session.document), 1)
        XCTAssertThrowsError(try MediaAssetEditing.prepare([fixture.audio, fixture.captions], document: session.document),
                             "A file an Image plays can't be removed")
        XCTAssertNoThrow(try MediaAssetEditing.prepare([fixture.video, fixture.captions], document: session.document),
                         "An unused file can be removed")

        var tampered = session.document
        let index = try XCTUnwrap(tampered.pages[0].nodes.firstIndex { $0.id == fixture.imageID })
        tampered.pages[0].nodes[index].properties.append(
            NodeProperty(key: .init(rawValue: CanonicalMediaPlayback.namespace + "volume"), value: .number(0.5)))
        XCTAssertThrowsError(try tampered.validate(), "The playback key set is closed")

        let properties = try node().properties
        XCTAssertFalse(CanonicalMediaPlayback.keepingAvailable(properties, mediaIDs: [])
            .contains { $0.key.rawValue.hasPrefix(CanonicalMediaPlayback.namespace) }, "Paste drops playback without its file")
        let withoutCaptions = CanonicalMediaPlayback.keepingAvailable(properties, mediaIDs: [fixture.video.id])
        XCTAssertNotNil(withoutCaptions.first { $0.key.rawValue == CanonicalMediaPlayback.assetKey })
        XCTAssertNil(withoutCaptions.first { $0.key.rawValue == CanonicalMediaPlayback.captionsKey })
        XCTAssertEqual(withoutCaptions.count, properties.count - 1)

        try session.execute(prepare(nil))
        XCTAssertFalse(try node().properties.contains { $0.key.rawValue.hasPrefix(CanonicalMediaPlayback.namespace) })
        XCTAssertNotNil(CanonicalImageStyle.resolve(try node()), "The Image and its poster stay")
        try session.undo()
        XCTAssertEqual(CanonicalMediaPlayback.resolve(try node()), authored)
        try session.undo(); try session.undo()
        XCTAssertNil(CanonicalMediaPlayback.resolve(try node()))
        try session.redo()
        XCTAssertEqual(CanonicalMediaPlayback.resolve(try node())?.captionsAssetID, fixture.captions.id)
    }

    // SF-0803-004/006/008: output uses native controls, metadata preload,
    // the Image as poster, a captions track and the original bytes; only
    // muted video autoplays; missing or damaged files block the build with a
    // content-free finding; Preview answers byte ranges.
    @MainActor
    func testMediaExportsNativeControlsPosterAndCaptionsAndNeverAutoplaysSound() throws {
        var fixture = try mediaFixture()
        let pageID = fixture.document.pages[0].id
        func apply(_ playback: CanonicalMediaPlayback) throws {
            let session = DocumentSession(document: fixture.document)
            try session.execute(MediaPlaybackEditing.prepare(playback, nodeID: fixture.imageID, pageID: pageID,
                                                             document: session.document))
            fixture.document = session.document
        }
        func compile(data: [ResourceID: Data]? = nil) -> StaticBuildCompilation {
            StaticBuildCompiler.compile(document: fixture.document, profileSelection: .init(profile: .development),
                resourceDescriptors: fixture.descriptors, resourceData: data ?? fixture.data)
        }
        func html(_ result: StaticBuildCompilation) throws -> String {
            try XCTUnwrap(result.plan?.files.first { $0.path == "index.html" }?.contents, "\(result.findings.map(\.code))")
        }
        let imageElement = "<img data-siteforge-node=\"\(fixture.imageID.rawValue.uuidString.lowercased())\""

        try apply(.init(assetID: fixture.video.id, captionsAssetID: fixture.captions.id, muted: true, autoplay: true))
        let video = compile()
        let markup = try html(video)
        XCTAssertTrue(markup.contains(" controls preload=\"metadata\" muted playsinline autoplay poster=\"assets/\(fixture.poster.contentHash).png\""), markup)
        XCTAssertTrue(markup.contains("<source src=\"assets/\(fixture.video.contentHash).mp4\" type=\"video/mp4\">"), markup)
        XCTAssertTrue(markup.contains("<track kind=\"captions\" src=\"assets/\(fixture.captions.contentHash).vtt\" srclang=\"en\" label=\"English\" default>"), markup)
        XCTAssertTrue(markup.contains("aria-label=\"Product tour\""))
        XCTAssertFalse(markup.contains(imageElement), "The Image becomes the video's poster")
        XCTAssertEqual(Set(video.plan?.binaryFiles.map(\.path) ?? []), [
            "assets/\(fixture.poster.contentHash).png", "assets/\(fixture.video.contentHash).mp4", "assets/\(fixture.captions.contentHash).vtt"])
        XCTAssertEqual(video.plan?.binaryFiles.first { $0.path.hasSuffix(".mp4") }?.contents, fixture.data[fixture.video.resourceID],
                       "Original bytes, never re-encoded")
        XCTAssertFalse(video.findings.contains { $0.code == "media-video-no-captions" })
        XCTAssertFalse(video.findings.contains { $0.code == "output-reference-unresolved" }, "\(video.findings.map(\.code))")
        // SF-1206-001 (ADR-0124): assets.manifest.txt lists every exported file type in asset-identity
        // order: the poster image with its pixel size, the video and its captions with their media type.
        let assetManifest = try XCTUnwrap(video.plan?.files.first { $0.path == "assets.manifest.txt" }?.contents)
        XCTAssertEqual(assetManifest.split(separator: "\n").compactMap { $0.split(separator: "\t").first.map(String.init) },
                       [fixture.poster.id.description, fixture.video.id.description, fixture.captions.id.description].sorted(), assetManifest)
        XCTAssertTrue(assetManifest.contains("\(fixture.poster.id.description)\tassets/\(fixture.poster.contentHash).png\t4x4"), assetManifest)
        XCTAssertTrue(assetManifest.contains("\(fixture.video.id.description)\tassets/\(fixture.video.contentHash).mp4\tvideo/mp4"), assetManifest)
        XCTAssertTrue(assetManifest.contains("\(fixture.captions.id.description)\tassets/\(fixture.captions.contentHash).vtt\ttext/vtt"), assetManifest)
        XCTAssertFalse(assetManifest.contains(fixture.audio.id.description), "Only exported files are listed")
        XCTAssertFalse(assetManifest.contains("intro") || assetManifest.contains("Intro"), "No names or file names")

        // SF-0803 / SF-1206-004 (ADR-0121): on a page in a folder the poster, the
        // source and the captions all start at the page's folder, so they resolve.
        var nestedDocument = fixture.document
        var tour = DocumentPage(name: "Tour", route: .init(rawValue: "/media/tour"))
        let movedIndex = try XCTUnwrap(nestedDocument.pages[0].nodes.firstIndex { $0.id == fixture.imageID })
        var moved = nestedDocument.pages[0].nodes.remove(at: movedIndex)
        let homeRootID = nestedDocument.pages[0].rootNodeIDs[0]
        let homeRootIndex = try XCTUnwrap(nestedDocument.pages[0].nodes.firstIndex { $0.id == homeRootID })
        nestedDocument.pages[0].nodes[homeRootIndex].childIDs.removeAll { $0 == fixture.imageID }
        moved.parent = .node(tour.rootNodeIDs[0])
        tour.nodes[0].childIDs.append(moved.id)
        tour.nodes.append(moved)
        nestedDocument.pages.append(tour)
        try nestedDocument.validate()
        let nestedVideo = StaticBuildCompiler.compile(document: nestedDocument, profileSelection: .init(profile: .development),
            resourceDescriptors: fixture.descriptors, resourceData: fixture.data)
        let tourMarkup = try XCTUnwrap(nestedVideo.plan?.files.first { $0.path == "media/tour.html" }?.contents,
                                       "\(nestedVideo.findings.map(\.code))")
        XCTAssertTrue(tourMarkup.contains(" poster=\"../assets/\(fixture.poster.contentHash).png\""), tourMarkup)
        XCTAssertTrue(tourMarkup.contains("<source src=\"../assets/\(fixture.video.contentHash).mp4\""), tourMarkup)
        XCTAssertTrue(tourMarkup.contains("<track kind=\"captions\" src=\"../assets/\(fixture.captions.contentHash).vtt\""), tourMarkup)
        XCTAssertFalse(nestedVideo.findings.contains { $0.code == "output-reference-unresolved" }, "\(nestedVideo.findings.map(\.code))")
        // OD-038 (ADR-0082): the French tree (`fr/`) writes the same video, and its
        // poster, source and captions start at that folder as well.
        var mediaFrenchDocument = fixture.document
        var mediaFrenchLocalization = try SiteLocalizationEditing.start(code: "en", name: "English")
        _ = try SiteLocalizationEditing.addLocale(code: "fr", name: "Français", to: &mediaFrenchLocalization)
        mediaFrenchDocument.localization = mediaFrenchLocalization
        try mediaFrenchDocument.validate()
        let mediaFrenchBuild = StaticBuildCompiler.compile(document: mediaFrenchDocument, profileSelection: .init(profile: .development),
            resourceDescriptors: fixture.descriptors, resourceData: fixture.data)
        let mediaFrenchMarkup = try XCTUnwrap(mediaFrenchBuild.plan?.files.first { $0.path == "fr/index.html" }?.contents,
                                              "\(mediaFrenchBuild.findings.map(\.code))")
        XCTAssertTrue(mediaFrenchMarkup.contains(" poster=\"../assets/\(fixture.poster.contentHash).png\""), mediaFrenchMarkup)
        XCTAssertTrue(mediaFrenchMarkup.contains("<source src=\"../assets/\(fixture.video.contentHash).mp4\""), mediaFrenchMarkup)
        XCTAssertTrue(mediaFrenchMarkup.contains("<track kind=\"captions\" src=\"../assets/\(fixture.captions.contentHash).vtt\""), mediaFrenchMarkup)
        XCTAssertEqual(Set(mediaFrenchBuild.plan?.binaryFiles.map(\.path) ?? []), Set(video.plan?.binaryFiles.map(\.path) ?? []),
                       "Every language uses the same written files")
        XCTAssertFalse(mediaFrenchBuild.findings.contains { $0.code == "output-reference-unresolved" }, "\(mediaFrenchBuild.findings.map(\.code))")

        let content = try WebsitePreviewHTTPContent(plan: try XCTUnwrap(video.plan))
        let videoBytes = try XCTUnwrap(fixture.data[fixture.video.resourceID])
        let ranged = content.response(to: Data("GET /assets/\(fixture.video.contentHash).mp4 HTTP/1.1\r\nHost: 127.0.0.1:8080\r\nRange: bytes=0-3\r\n\r\n".utf8), port: 8080)
        XCTAssertEqual(ranged.status, 206)
        XCTAssertEqual(ranged.body, Data(videoBytes.prefix(4)))
        XCTAssertEqual(ranged.contentRange, "bytes 0-3/\(videoBytes.count)")
        XCTAssertTrue(String(decoding: ranged.bytes, as: UTF8.self).contains("Accept-Ranges: bytes"))
        let whole = content.response(to: Data("GET /assets/\(fixture.video.contentHash).mp4 HTTP/1.1\r\nHost: 127.0.0.1:8080\r\n\r\n".utf8), port: 8080)
        XCTAssertEqual(whole.status, 200); XCTAssertEqual(whole.type, "video/mp4"); XCTAssertEqual(whole.body, videoBytes)
        XCTAssertEqual(WebsitePreviewHTTPContent.byteRange("bytes=4-", count: 10), 4..<10)
        XCTAssertEqual(WebsitePreviewHTTPContent.byteRange("bytes=-3", count: 10), 7..<10)
        XCTAssertEqual(WebsitePreviewHTTPContent.byteRange("bytes=8-100", count: 10), 8..<10)
        XCTAssertEqual(WebsitePreviewHTTPContent.byteRange("bytes=8-\(Int.max)", count: 10), 8..<10)
        XCTAssertNil(WebsitePreviewHTTPContent.byteRange("bytes=10-", count: 10))
        XCTAssertNil(WebsitePreviewHTTPContent.byteRange("bytes=0-1,4-5", count: 10))
        XCTAssertNil(WebsitePreviewHTTPContent.byteRange("bytes=5-2", count: 10))
        XCTAssertNil(WebsitePreviewHTTPContent.byteRange("items=0-1", count: 10))

        try apply(.init(assetID: fixture.audio.id, loop: true))
        let audio = try html(compile())
        XCTAssertTrue(audio.contains(" controls preload=\"metadata\" loop aria-label=\"Product tour\">"), audio)
        XCTAssertTrue(audio.contains("<source src=\"assets/\(fixture.audio.contentHash).mp3\" type=\"audio/mpeg\">"), audio)
        XCTAssertFalse(audio.contains(" autoplay")); XCTAssertFalse(audio.contains("poster="))

        try apply(.init(assetID: fixture.video.id))
        let plain = compile()
        XCTAssertTrue(plain.findings.contains { $0.code == "media-video-no-captions" && $0.affectedNodeID == fixture.imageID })
        XCTAssertFalse(try html(plain).contains(" autoplay"))
        XCTAssertFalse(plain.plan?.binaryFiles.contains { $0.path.hasSuffix(".vtt") } ?? true, "Unused files are not exported")
        let unplanned = try MultiPageStaticBuildPlanner.plan(document: fixture.document).files.map(\.contents).joined()
        XCTAssertTrue(unplanned.contains("data-siteforge-media-state=\"missing\""), "No verified file means no source URL")

        var missingData = fixture.data
        missingData[fixture.video.resourceID] = nil
        let missing = compile(data: missingData)
        XCTAssertNil(missing.plan)
        XCTAssertTrue(missing.findings.contains { $0.code == "media-missing" && $0.affectedNodeID == fixture.imageID })
        XCTAssertFalse(missing.findings.contains { $0.explanation.contains(fixture.video.displayName) }, "Findings carry no names")
        let damaged = Data("<html>".utf8)
        let damagedDescriptor = ProjectResourceDescriptor(id: ResourceID(), filename: "x.mp4", mediaType: "video/mp4",
                                                          byteCount: damaged.count, sha256: ProjectResourceStore.digest(damaged))
        XCTAssertThrowsError(try StaticAssetExportPlanner.plan(index: .init(resources: [damagedDescriptor]),
                                                               blobs: [damagedDescriptor.sha256: damaged])) {
            XCTAssertEqual($0 as? StaticAssetExportError, .corrupt)
        }

        func sniff(_ bytes: [UInt8], _ ext: String) -> MediaAssetFormat? {
            ProjectMediaFormatSniffer.format(of: Data(bytes), fileExtension: ext)
        }
        let padding = [UInt8](repeating: 0, count: 8)
        XCTAssertEqual(sniff([0, 0, 0, 0x18] + Array("ftypM4A ".utf8) + padding, "mp4"), .m4a)
        XCTAssertEqual(sniff([0, 0, 0, 0x18] + Array("ftypisom".utf8) + padding, "m4a"), .m4a)
        XCTAssertNil(sniff([0, 0, 0, 0x14] + Array("ftypqt  ".utf8) + padding, "mov"), "QuickTime is not a web format")
        XCTAssertEqual(sniff([0x1A, 0x45, 0xDF, 0xA3, 0x9F, 0x42, 0x82, 0x84] + Array("webm".utf8), "webm"), .webm)
        XCTAssertNil(sniff([0x1A, 0x45, 0xDF, 0xA3, 0x9F, 0x42, 0x82, 0x88] + Array("matroska".utf8), "mkv"))
        XCTAssertEqual(sniff(Array("OggS".utf8) + padding, "ogg"), .ogg)
        XCTAssertEqual(sniff(Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WAVE".utf8), "wav"), .wav)
        XCTAssertEqual(sniff([0xFF, 0xFB, 0x90, 0x00], "mp3"), .mp3)
        XCTAssertNil(sniff([0xFF, 0xF1, 0x50, 0x80], "mp3"), "AAC ADTS is not MP3")
        XCTAssertNil(sniff([0xFF, 0xFB, 0x90, 0x00], "aac"))
        XCTAssertEqual(sniff([0xEF, 0xBB, 0xBF] + Array("WEBVTT\n".utf8), "vtt"), .vtt)
        XCTAssertEqual(sniff(Array("WEBVTT".utf8), "vtt"), .vtt)
        XCTAssertNil(sniff(Array("WEBVTTX".utf8), "vtt"))
    }

    // SF-0803-004/005: import keeps the original bytes and refuses other
    // types; workspace edits are one undoable step each; removal keeps the
    // bytes for Undo; files and bytes survive save and reopen.
    @MainActor func testMediaImportKeepsOriginalBytesAndMediaSurvivesSaveAndReopen() async throws {
        let directory = try makeFixture()
        let unsupported = directory.url.appendingPathComponent("clip.mov")
        try Data([0, 0, 0, 0x14] + Array("ftypqt  ".utf8) + [UInt8](repeating: 0, count: 8)).write(to: unsupported)
        do { _ = try await MediaImportWorker().prepare(url: unsupported); XCTFail("QuickTime is not accepted") }
        catch { XCTAssertEqual(error as? MediaImportError, .unsupported) }
        let damaged = directory.url.appendingPathComponent("broken.mp4")
        try Data("not a video".utf8).write(to: damaged)
        do { _ = try await MediaImportWorker().prepare(url: damaged); XCTFail("A file that is not what its name says is refused") }
        catch { XCTAssertEqual(error as? MediaImportError, .corrupt) }
        let captionsURL = directory.url.appendingPathComponent("Intro captions.vtt")
        let captionsBytes = Data("WEBVTT\n\n00:00.000 --> 00:01.000\nHello\n".utf8)
        try captionsBytes.write(to: captionsURL)
        let prepared = try await MediaImportWorker().prepare(url: captionsURL)
        XCTAssertEqual(prepared.media.format, .vtt); XCTAssertEqual(prepared.descriptor.mediaType, "text/vtt")
        XCTAssertEqual(prepared.media.displayName, "Intro captions"); XCTAssertNil(prepared.media.language)
        XCTAssertEqual(prepared.data, captionsBytes)
        XCTAssertEqual(prepared.media.contentHash, ProjectResourceStore.digest(captionsBytes))

        let session = DocumentSession(document: ProjectCreation.blank())
        let lifecycle = DocumentLifecycleController(session: session, recoveryDirectory: directory.url.appendingPathComponent("media-recovery"))
        _ = try lifecycle.installingProjectResource(prepared.descriptor, data: prepared.data) {
            try session.execute(MediaAssetEditing.prepare([prepared.media], document: session.document))
        }
        let state = WorkspaceShellState(documentSession: session, lifecycle: lifecycle)
        XCTAssertTrue(state.mediaResourceIsAvailable(prepared.media))
        let history = session.historySnapshot().undoEntries.count
        var english = prepared.media
        english.language = "en"
        XCTAssertTrue(state.updateMediaAsset(english))
        XCTAssertEqual(session.historySnapshot().undoEntries.count, history + 1)
        var invalid = english
        invalid.language = "not a tag"
        XCTAssertFalse(state.updateMediaAsset(invalid))
        XCTAssertEqual(session.document.mediaAssets, [english])
        XCTAssertEqual(session.historySnapshot().undoEntries.count, history + 1)
        XCTAssertTrue(state.removeMediaAsset(english.id))
        XCTAssertTrue(session.document.mediaAssets.isEmpty)
        XCTAssertEqual(try lifecycle.projectResourceData(for: english.resourceID), captionsBytes, "Removing keeps the bytes for Undo")
        try session.undo()
        XCTAssertEqual(session.document.mediaAssets, [english])
        // SF-0803-008: each workspace edit leaves one bounded, content-free record.
        let records = state.mediaAssetDiagnosticRecords
        XCTAssertEqual(records.map(\.operation), [.mediaUpdate, .mediaUpdate, .mediaRemove])
        XCTAssertEqual(records.map(\.succeeded), [true, false, true])
        XCTAssertEqual(records.map(\.requirementID), ["SF-0803-002", "SF-0803-002", "SF-0803-005"])
        XCTAssertEqual(records[1].failureCategory, "invalid-input")
        let evidence = String(describing: records)
        for secret in ["Intro captions", "not a tag", english.id.description, directory.url.path] {
            XCTAssertFalse(evidence.contains(secret), "Diagnostics must not contain \(secret)")
        }
        let snapshot = try ProjectImageResourceSnapshot(document: session.document, package: lifecycle.staticBuildResourceSnapshot())
        XCTAssertEqual(snapshot.data[english.resourceID], captionsBytes, "Builds receive media bytes")
        let package = directory.url.appendingPathComponent("Media.siteforge")
        let saved = await lifecycle.save(to: package); XCTAssertTrue(saved)
        let reader = DocumentLifecycleController(session: DocumentSession(), recoveryDirectory: directory.url.appendingPathComponent("media-reader-recovery"))
        let opened = await reader.requestOpen(package); XCTAssertEqual(opened, .completed)
        XCTAssertEqual(reader.session.document.mediaAssets, [english])
        XCTAssertEqual(try reader.projectResourceData(for: english.resourceID), captionsBytes)
    }

    // OD-045 / SF-0805 / SF-0803: a new project's resources (a packaged
    // template) must include every font and media file its document lists,
    // not only its images.
    func testProjectCreationResourcesRequireEveryFontAndMediaFile() throws {
        let fixture = try mediaFixture()
        func creationPackage(excluding excluded: ResourceID?) throws -> ProjectPackage {
            var result = ProjectPackage(document: fixture.document, optionalMembers: [])
            for (id, descriptor) in fixture.descriptors.sorted(by: { $0.key.description < $1.key.description }) where id != excluded {
                result = try result.withResource(descriptor, data: try XCTUnwrap(fixture.data[id]))
            }
            return result
        }
        XCTAssertEqual(ProjectCreationResources.storedFiles(in: fixture.document).count, 4, "Poster, video, audio and captions")
        XCTAssertNoThrow(try ProjectCreationResources.validate(document: fixture.document,
                                                              members: creationPackage(excluding: nil).optionalMembers))
        XCTAssertThrowsError(try ProjectCreationResources.validate(document: fixture.document,
            members: creationPackage(excluding: fixture.captions.resourceID).optionalMembers), "A missing captions file is refused") {
            XCTAssertEqual($0 as? ProjectResourceError, .missingBlob)
        }
    }

    // SF-0803-005 / SF-0805-005: font and media edits are kept in the saved
    // edit history (persisted-history schema 4) and restore with exact inverses.
    @MainActor func testFontAndMediaEditsRestoreFromPersistedHistory() async throws {
        let fixture = try mediaFixture()
        let fontBytes = Data([0x00, 0x01, 0x00, 0x00] + Array(repeating: UInt8(5), count: 60))
        let font = FontAsset(resourceID: ResourceID(), family: "History Sans", format: .ttf, originalFilename: "history.ttf",
                             byteCount: fontBytes.count, contentHash: ProjectResourceStore.digest(fontBytes))
        let blank = ProjectCreation.blank()
        let session = DocumentSession(document: blank)
        try session.execute(FontAssetEditing.prepare([font], document: session.document))
        try session.execute(MediaAssetEditing.prepare([fixture.captions], document: session.document))
        let store = PersistedHistoryStore()
        let history = try await store.encodeRetained(session.historySnapshot())
        let text = String(decoding: history, as: UTF8.self)
        XCTAssertTrue(text.contains("\"setFontAssets\"")); XCTAssertTrue(text.contains("\"setMediaAssets\""))
        let loaded = try await store.load(from: ProjectPackage(document: session.document,
            optionalMembers: [.init(path: PersistedHistoryStore.memberPath, data: history)]))
        guard case .restored(let snapshot) = loaded else { return XCTFail("Font and media history must restore: \(loaded)") }
        XCTAssertEqual(Set(snapshot.undoEntries.map(\.commandName)), [.setFontAssets, .setMediaAssets])
        XCTAssertTrue(snapshot.undoEntries.contains { $0.inverse == .setFontAssets(.init(documentID: blank.id, fontAssets: [])) })
        XCTAssertTrue(snapshot.undoEntries.contains { $0.inverse == .setMediaAssets(.init(documentID: blank.id, mediaAssets: [])) })
    }

    // SF-0805-003/007 (lane V08): canvas faces are registered off the main
    // actor, counted per window and released when they leave the document, so
    // a removed face shows its fallback; bytes Core Text refuses are not retried.
    func testProjectFontCanvasSessionReleasesRemovedFacesAndNeverRetriesRefusedBytes() async throws {
        func fontPackage(_ font: FontAsset, _ bytes: Data) throws -> ProjectPackage {
            var document = ProjectCreation.blank()
            document.fontAssets = [font]
            return try ProjectPackage(document: document, optionalMembers: []).withResource(
                ProjectResourceDescriptor(id: font.resourceID, filename: font.originalFilename, mediaType: font.format.mediaType,
                                          byteCount: bytes.count, sha256: font.contentHash), data: bytes)
        }
        let fake = Data([0x00, 0x01, 0x00, 0x00] + Array(repeating: UInt8(4), count: 60))
        let refusedFont = FontAsset(resourceID: ResourceID(), family: "Refused Sans", format: .ttf, originalFilename: "refused.ttf",
                                    byteCount: fake.count, contentHash: ProjectResourceStore.digest(fake))
        let session = ProjectFontCanvasSession()
        let refusedPackage = try fontPackage(refusedFont, fake)
        let refused = await session.update(fonts: [refusedFont], package: refusedPackage)
        XCTAssertFalse(refused, "Bytes Core Text can't load leave the canvas unchanged")
        XCTAssertEqual(ProjectFontCanvasRegistration.userCount(contentHash: refusedFont.contentHash), 0)
        XCTAssertFalse(ProjectFontCanvasRegistration.release(format: .ttf, contentHash: refusedFont.contentHash),
                       "A face that was never registered has nothing to release")
        let absent = FontAsset(resourceID: ResourceID(), family: "Absent Sans", format: .ttf, originalFilename: "absent.ttf",
                               byteCount: 4, contentHash: String(repeating: "c", count: 64))
        let missing = await session.update(fonts: [absent], package: refusedPackage)
        XCTAssertFalse(missing, "A file that is not in the project changes nothing")
        let cleared = await session.update(fonts: [], package: refusedPackage)
        XCTAssertFalse(cleared, "Nothing was registered, so nothing is released")

        let system = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Arial.ttf")
        guard let bytes = try? Data(contentsOf: system) else { return }
        let arial = FontAsset(resourceID: ResourceID(), family: "Arial", format: .ttf, originalFilename: "Arial.ttf",
                              byteCount: bytes.count, contentHash: ProjectResourceStore.digest(bytes))
        let arialPackage = try fontPackage(arial, bytes)
        let before = ProjectFontCanvasRegistration.userCount(contentHash: arial.contentHash)
        let added = await session.update(fonts: [arial], package: arialPackage)
        // Core Text may refuse a second copy of an installed face; counting is
        // checked whenever it accepts the copy.
        guard added else { return }
        XCTAssertEqual(ProjectFontCanvasRegistration.userCount(contentHash: arial.contentHash), before + 1)
        let repeated = await session.update(fonts: [arial], package: arialPackage)
        XCTAssertFalse(repeated, "An unchanged face is not registered twice")
        XCTAssertEqual(ProjectFontCanvasRegistration.userCount(contentHash: arial.contentHash), before + 1)
        _ = await session.update(fonts: [], package: arialPackage)
        XCTAssertEqual(ProjectFontCanvasRegistration.userCount(contentHash: arial.contentHash), before,
                       "A face that leaves the document is released")
    }

    // SF-0805-004 (lane V08, OD-060): a WOFF2 file with an intact header that
    // Core Text can't read gets its own message and recovery; a damaged
    // header stays "damaged".
    func testWOFF2ImportTellsUnreadableFilesFromDamagedOnes() async throws {
        let fixture = try makeFixture()
        var header = [UInt8](repeating: 0, count: 64)
        header[0...3] = [0x77, 0x4F, 0x46, 0x32]
        header[4...7] = [0x00, 0x01, 0x00, 0x00]
        header[11] = 64 // length: the whole file
        header[13] = 1 // numTables
        XCTAssertTrue(ProjectFontFormatSniffer.hasValidWOFF2Header(Data(header)))
        let unreadable = fixture.url.appendingPathComponent("brand.woff2")
        try Data(header).write(to: unreadable)
        do { _ = try await FontImportWorker().prepare(url: unreadable); XCTFail("Core Text can't read these tables") }
        catch { XCTAssertEqual(error as? FontImportError, .unreadableWOFF2) }
        var truncated = header
        truncated[11] = 99 // length no longer matches the file
        XCTAssertFalse(ProjectFontFormatSniffer.hasValidWOFF2Header(Data(truncated)))
        XCTAssertFalse(ProjectFontFormatSniffer.hasValidWOFF2Header(Data(header.prefix(20))))
        let damaged = fixture.url.appendingPathComponent("damaged.woff2")
        try Data(truncated).write(to: damaged)
        do { _ = try await FontImportWorker().prepare(url: damaged); XCTFail("A damaged header is refused") }
        catch { XCTAssertEqual(error as? FontImportError, .corrupt) }
        XCTAssertEqual(FontImportError.unreadableWOFF2.diagnosticCategory, "unreadable-woff2")
        XCTAssertTrue(FontImportError.unreadableWOFF2.errorDescription?.contains("TrueType (.ttf)") == true)
    }

    // SF-0804-003 (lane V08): the Image Inspector names the rule that gives an
    // SVG Image its accessible name, without repeating any of its text.
    func testSVGAccessibleNameExplanationNamesTheWinningRule() {
        XCTAssertTrue(SVGAssetSanitizer.accessibleNameExplanation(altText: "Logo", isDecorative: false, svgTitle: "Brand")
            .hasPrefix("Named by this Image's alternative text"))
        let suggestion = SVGAssetSanitizer.accessibleNameExplanation(altText: " ", isDecorative: false, svgTitle: "Brand")
        XCTAssertTrue(suggestion.contains("only a suggestion")); XCTAssertFalse(suggestion.contains("Brand"))
        XCTAssertTrue(SVGAssetSanitizer.accessibleNameExplanation(altText: "Logo", isDecorative: true, svgTitle: "Brand")
            .hasPrefix("Decorative"))
        XCTAssertTrue(SVGAssetSanitizer.accessibleNameExplanation(altText: "", isDecorative: false, svgTitle: nil)
            .contains("has no title"))
    }

    // SF-0803-007 / SF-0804-007 / SF-0805-007 (lane V08): standard (100) and
    // large (10,000 objects) fixtures. Validation and the derived checks that
    // the Inspector, the sheets and builds run after each change stay within
    // generous safety bounds (they catch accidental quadratic work, not
    // machine speed); a 10,000-element SVG is sanitized and recolored too.
    func testMediaFontAndSVGChecksStayWithinBoundsOnStandardAndLargeFixtures() throws {
        let clock = ContinuousClock()
        let icon = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">"
            + String(repeating: "<path d=\"M0 0h1v1H0z\" fill=\"#000000\"/>", count: 10_000) + "</svg>"
        var sanitized: SanitizedSVG?
        let sanitizing = try clock.measure { sanitized = try SVGAssetSanitizer.sanitize(Data(icon.utf8)) }
        let svg = try XCTUnwrap(sanitized)
        XCTAssertEqual(svg.report.paintColors, ["#000000"]); XCTAssertTrue(svg.report.isRecolorCompatible)
        var recolored: SanitizedSVG?
        let recoloring = try clock.measure { recolored = try SVGAssetSanitizer.recolor(svg.data, to: "#336699") }
        XCTAssertEqual(recolored?.report.paintColors, ["#336699"])
        XCTAssertLessThan(sanitizing + recoloring, .seconds(60), "10,000-element SVG: safety bound only")

        for (count, bound) in [(100, Duration.seconds(10)), (10_000, .seconds(120))] {
            var fixture = try mediaFixture()
            let fontBytes = Data([0x00, 0x01, 0x00, 0x00] + Array(repeating: UInt8(6), count: 60))
            fixture.document.fontAssets = [FontAsset(resourceID: ResourceID(), family: "Scale Sans", format: .ttf,
                originalFilename: "scale.ttf", byteCount: fontBytes.count, contentHash: ProjectResourceStore.digest(fontBytes))]
            let root = fixture.document.pages[0].rootNodeIDs[0]
            let rootIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == root })
            for index in 0..<(count / 2) {
                let x = Double(index % 50) * 20, y = Double(index / 50) * 20
                let textProperties: [(String, PropertyValue)] = [
                    ("layout.x", .number(x)), ("layout.y", .number(y)), ("layout.width", .number(18)), ("layout.height", .number(18)),
                    ("content.text", .string("\(index)")),
                    (CanonicalTypography.namespace + "family", .string("Scale Sans")),
                    (CanonicalTypography.namespace + "weight", .string("regular")),
                    (CanonicalTypography.namespace + "size", .number(12)),
                    (CanonicalTypography.namespace + "lineHeight", .number(16)),
                    (CanonicalTypography.namespace + "tracking", .number(0)),
                    (CanonicalTypography.namespace + "alignment", .string("leading")),
                ]
                let clipProperties: [(String, PropertyValue)] = [
                    ("layout.x", .number(x)), ("layout.y", .number(y + 1_000)), ("layout.width", .number(18)), ("layout.height", .number(18)),
                    (CanonicalImageStyle.namespace + "assetID", .string(fixture.poster.id.description)),
                    (CanonicalImageStyle.namespace + "fit", .string(ImageFitMode.fill.rawValue)),
                    (CanonicalImageStyle.namespace + "focal.x", .number(0.5)), (CanonicalImageStyle.namespace + "focal.y", .number(0.5)),
                    (CanonicalImageStyle.namespace + "alt", .string("Clip")), (CanonicalImageStyle.namespace + "decorative", .boolean(false)),
                    (CanonicalMediaPlayback.assetKey, .string(fixture.video.id.description)),
                    (CanonicalMediaPlayback.captionsKey, .string(fixture.captions.id.description)),
                ]
                let text = DocumentNode(kind: .text, name: "Copy \(index)", parent: .node(root),
                                        properties: textProperties.map { NodeProperty(key: .init(rawValue: $0.0), value: $0.1) })
                let clip = DocumentNode(kind: .image, name: "Clip \(index)", parent: .node(root),
                                        properties: clipProperties.map { NodeProperty(key: .init(rawValue: $0.0), value: $0.1) })
                fixture.document.pages[0].nodes[rootIndex].childIDs += [text.id, clip.id]
                fixture.document.pages[0].nodes += [text, clip]
            }
            let document = fixture.document
            let nodes = document.pages.flatMap(\.nodes)
            var fontUses = 0, videoUses = 0
            var candidates: [MediaAsset] = []
            var findings: [StaticBuildFinding] = []
            let elapsed = try clock.measure {
                try document.validate()
                fontUses = ProjectFontResolver.usageCount(family: "scale sans", in: document)
                videoUses = MediaAssetEditing.usageCount(fixture.video.id, in: document)
                candidates = ProjectMediaOutput.exportCandidates(nodes: nodes, document: document)
                findings = ProjectFontOutput.findings(document: document) + ProjectMediaOutput.findings(nodes: nodes, document: document)
            }
            XCTAssertEqual(fontUses, count / 2); XCTAssertEqual(videoUses, count / 2)
            XCTAssertEqual(Set(candidates.map(\.id)), [fixture.video.id, fixture.captions.id])
            XCTAssertTrue(findings.contains { $0.code == "font-rights-unconfirmed" })
            XCTAssertFalse(findings.contains { $0.code == "media-video-no-captions" })
            XCTAssertLessThan(elapsed, bound, "\(count) objects: safety bound only")
        }
    }

    private struct MediaTestFixture {
        var document: CanonicalDocument
        let imageID: NodeID
        let poster: ImageAsset
        let video: MediaAsset
        let audio: MediaAsset
        let captions: MediaAsset
        let descriptors: [ResourceID: ProjectResourceDescriptor]
        let data: [ResourceID: Data]
    }

    /// One page with one Image (poster), plus a video, an audio and an
    /// English captions file in the project. Playback starts off.
    private func mediaFixture() throws -> MediaTestFixture {
        let posterBytes = representativeAsset(index: 7)
        let poster = ImageAsset(resourceID: ResourceID(), displayName: "Poster", originalFilename: "poster.png", format: .png,
                                pixelWidth: 4, pixelHeight: 4, byteCount: posterBytes.count,
                                contentHash: ProjectResourceStore.digest(posterBytes))
        let videoBytes = Data([0x00, 0x00, 0x00, 0x18] + Array("ftypisom".utf8) + [UInt8](repeating: 1, count: 52))
        let audioBytes = Data(Array("ID3".utf8) + [0x03, 0x00, 0x00] + [UInt8](repeating: 2, count: 58))
        let captionsBytes = Data("WEBVTT\n\n00:00.000 --> 00:01.000\nHello\n".utf8)
        func media(_ name: String, _ file: String, _ format: MediaAssetFormat, _ bytes: Data, language: String? = nil) -> MediaAsset {
            MediaAsset(resourceID: ResourceID(), displayName: name, originalFilename: file, format: format,
                       byteCount: bytes.count, contentHash: ProjectResourceStore.digest(bytes), language: language)
        }
        let video = media("Intro", "intro.mp4", .mp4, videoBytes)
        let audio = media("Theme", "theme.mp3", .mp3, audioBytes)
        let captions = media("English", "intro.en.vtt", .vtt, captionsBytes, language: "en")
        var document = ProjectCreation.blank()
        document.imageAssets = [poster]
        document.mediaAssets = [video, audio, captions]
        let root = document.pages[0].rootNodeIDs[0]
        let image = DocumentNode(kind: .image, name: "Intro video", parent: .node(root), properties: [
            ("layout.x", PropertyValue.number(0)), ("layout.y", .number(0)), ("layout.width", .number(320)), ("layout.height", .number(180)),
            (CanonicalImageStyle.namespace + "assetID", .string(poster.id.description)),
            (CanonicalImageStyle.namespace + "fit", .string(ImageFitMode.fill.rawValue)),
            (CanonicalImageStyle.namespace + "focal.x", .number(0.5)), (CanonicalImageStyle.namespace + "focal.y", .number(0.5)),
            (CanonicalImageStyle.namespace + "alt", .string("Product tour")), (CanonicalImageStyle.namespace + "decorative", .boolean(false)),
        ].map { NodeProperty(key: .init(rawValue: $0.0), value: $0.1) })
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == root })
        document.pages[0].nodes[rootIndex].childIDs.append(image.id)
        document.pages[0].nodes.append(image)
        try document.validate()
        let files: [(ResourceID, String, String, Data)] = [
            (poster.resourceID, "poster.png", "image/png", posterBytes),
            (video.resourceID, "intro.mp4", "video/mp4", videoBytes),
            (audio.resourceID, "theme.mp3", "audio/mpeg", audioBytes),
            (captions.resourceID, "intro.en.vtt", "text/vtt", captionsBytes),
        ]
        var descriptors: [ResourceID: ProjectResourceDescriptor] = [:]
        var data: [ResourceID: Data] = [:]
        for (id, file, type, bytes) in files {
            descriptors[id] = ProjectResourceDescriptor(id: id, filename: file, mediaType: type, byteCount: bytes.count,
                                                        sha256: ProjectResourceStore.digest(bytes))
            data[id] = bytes
        }
        return MediaTestFixture(document: document, imageID: image.id, poster: poster, video: video, audio: audio,
                                captions: captions, descriptors: descriptors, data: data)
    }

    // SF-0804-006/008, SF-0805-003/006/008: menu, Assets buttons and row
    // menus share one presentation state; every media operation leaves a
    // bounded, content-free diagnostic; canvas registration only accepts
    // verified bytes of the declared format.
    @MainActor func testMediaAssetCommandsShareStateAndRecordContentFreeDiagnostics() async throws {
        let fixture = try makeFixture()
        let svg = Data(##"<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><title>Secret brand</title><path d="M0 0h8v8z" fill="#000000"/></svg>"##.utf8)
        let sanitized = try SVGAssetSanitizer.sanitize(svg).data
        let asset = ImageAsset(resourceID: ResourceID(), displayName: "Mark", originalFilename: "mark.svg", format: .svg,
                               pixelWidth: 8, pixelHeight: 8, byteCount: sanitized.count, contentHash: ProjectResourceStore.digest(sanitized))
        let pngBytes = try makePNG(width: 2, height: 2)
        let raster = ImageAsset(resourceID: ResourceID(), displayName: "Photo", originalFilename: "photo.png", format: .png,
                                pixelWidth: 2, pixelHeight: 2, byteCount: pngBytes.count, contentHash: ProjectResourceStore.digest(pngBytes))
        let fontBytes = Data([0x00, 0x01, 0x00, 0x00] + Array(repeating: UInt8(9), count: 60))
        let font = FontAsset(resourceID: ResourceID(), family: "Secret Sans", format: .ttf, originalFilename: "secret.ttf",
                             byteCount: fontBytes.count, contentHash: ProjectResourceStore.digest(fontBytes))
        let session = DocumentSession(document: ProjectCreation.blank())
        let lifecycle = DocumentLifecycleController(session: session, recoveryDirectory: fixture.url.appendingPathComponent("media-recovery"))
        for (asset, bytes) in [(asset, sanitized), (raster, pngBytes)] {
            let descriptor = ProjectResourceDescriptor(id: asset.resourceID, filename: asset.originalFilename,
                mediaType: asset.format.mediaType, byteCount: bytes.count, sha256: asset.contentHash)
            _ = try lifecycle.installingProjectResource(descriptor, data: bytes) {
                try session.execute(.insertImageAsset(.init(asset: asset, index: session.document.imageAssets.count)))
            }
        }
        let fontDescriptor = ProjectResourceDescriptor(id: font.resourceID, filename: font.originalFilename, mediaType: "font/ttf",
                                                       byteCount: fontBytes.count, sha256: font.contentHash)
        _ = try lifecycle.installingProjectResource(fontDescriptor, data: fontBytes) {
            try session.execute(FontAssetEditing.prepare([font], document: session.document))
        }
        let state = WorkspaceShellState(documentSession: session, lifecycle: lifecycle)

        state.selectedAssetID = raster.id
        XCTAssertFalse(state.canRecolorSVG())
        state.presentSVGRecolor()
        XCTAssertNil(state.svgRecolorAssetID, "A raster selection cannot open the recolor sheet")
        state.selectedAssetID = asset.id
        XCTAssertTrue(state.canRecolorSVG())
        state.presentSVGRecolor()
        XCTAssertEqual(state.svgRecolorAssetID, asset.id)
        XCTAssertTrue(state.canManageProjectFonts)
        state.presentProjectFonts()
        XCTAssertTrue(state.isProjectFontsPresented)
        // SF-0803-006: File ▸ Video & Audio… and the Assets button share one state.
        XCTAssertTrue(state.canManageProjectMedia)
        state.presentProjectMedia()
        XCTAssertTrue(state.isProjectMediaPresented)

        XCTAssertTrue(state.recolorSVGAsset(asset.id, hex: "#336699"))
        XCTAssertFalse(state.recolorSVGAsset(raster.id, hex: "#336699"))
        var renamed = font
        renamed.weight = 450
        XCTAssertFalse(state.updateFontAsset(renamed))
        var confirmed = font
        confirmed.rights = .webEmbeddingAllowed
        XCTAssertTrue(state.updateFontAsset(confirmed))
        XCTAssertTrue(state.removeFontAsset(font.id))

        let records = state.mediaAssetDiagnosticRecords
        XCTAssertEqual(records.map(\.operation), [.svgRecolor, .svgRecolor, .fontUpdate, .fontUpdate, .fontRemove])
        XCTAssertEqual(records.map(\.succeeded), [true, false, false, true, true])
        XCTAssertEqual(records[1].failureCategory, "unsupported-format")
        XCTAssertEqual(records[2].failureCategory, "invalid-input")
        XCTAssertEqual(records[0].requirementID, "SF-0804-002")
        XCTAssertEqual(records[4].requirementID, "SF-0805-005")
        let evidence = String(describing: records)
        for secret in ["Secret", "secret.ttf", "mark.svg", "#336699", asset.id.description, font.id.description, fixture.url.path] {
            XCTAssertFalse(evidence.contains(secret), "Diagnostics must not contain \(secret)")
        }
        XCTAssertTrue(records.allSatisfy { $0.sanitizedAssetID?.hasPrefix("asset-") == true })

        XCTAssertFalse(ProjectFontCanvasRegistration.register(fontBytes, format: .woff2, contentHash: font.contentHash),
                       "The declared format must match the file signature")
        XCTAssertFalse(ProjectFontCanvasRegistration.register(fontBytes, format: .ttf, contentHash: String(repeating: "0", count: 64)),
                       "Bytes must match their content hash")
    }

    private func makeFixture() throws -> ApplicationOwnedTestFixture {
        let fixture = try ApplicationOwnedTestFixture.create("resources")
        fixtures.append(fixture)
        return fixture
    }

    private func representativeAsset(index: Int) -> Data {
        var data = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        data.append(Data(repeating: UInt8(truncatingIfNeeded: index), count: 32 * 1_024 - data.count))
        return data
    }

    private func makePNG(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.16, green: 0.48, blue: 0.72, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func descriptor(id: String, bytes: Data) -> ProjectResourceDescriptor {
        ProjectResourceDescriptor(
            id: ResourceID(uuidString: id)!, filename: "asset.bin", mediaType: "application/octet-stream",
            byteCount: bytes.count, sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap((attributes[.posixPermissions] as? NSNumber)?.intValue)
    }

    private func run(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}

private actor ResourceStoreDescriptorBarrier {
    private var hasReached = false
    private var reachedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    nonisolated func reachAndWait() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await markReached()
            await waitForRelease()
            semaphore.signal()
        }
        semaphore.wait()
    }

    func waitUntilReached() async {
        if hasReached { return }
        await withCheckedContinuation { reachedContinuation = $0 }
    }

    nonisolated func release() { Task { await releaseNow() } }

    private func markReached() {
        hasReached = true
        reachedContinuation?.resume()
        reachedContinuation = nil
    }

    private func waitForRelease() async {
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    private func releaseNow() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor ResourceCancellationBarrier {
    private let blockAt: Int
    private var count = 0
    private var blockedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(blockAt: Int) { self.blockAt = blockAt }

    nonisolated func check() throws {
        try Task.checkCancellation()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let shouldBlock = await checkpoint()
            if shouldBlock { await waitForRelease() }
            semaphore.signal()
        }
        semaphore.wait()
        try Task.checkCancellation()
    }

    func waitUntilBlocked() async {
        if count >= blockAt { return }
        await withCheckedContinuation { blockedContinuation = $0 }
    }

    nonisolated func release() { Task { await releaseNow() } }

    private func checkpoint() -> Bool {
        count += 1
        if count == blockAt {
            blockedContinuation?.resume()
            blockedContinuation = nil
            return true
        }
        return false
    }

    private func waitForRelease() async { await withCheckedContinuation { releaseContinuation = $0 } }
    private func releaseNow() { releaseContinuation?.resume(); releaseContinuation = nil }
}

private func XCTAssertThrowsErrorAsync<T: Sendable>(
    _ expression: @autoclosure () async throws -> T,
    equals expected: ProjectResourceError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? ProjectResourceError, expected, file: file, line: line)
    }
}
