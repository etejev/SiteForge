import CryptoKit
import Combine
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SiteForge

final class ProjectResourceTests: XCTestCase {

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
