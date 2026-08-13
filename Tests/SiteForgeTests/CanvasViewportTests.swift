import XCTest
@testable import SiteForge

final class CanvasViewportTests: XCTestCase {
    // SF-0401-001, SF-0401-003, SF-0401-005 — a new/adopted workspace fits
    // the noncanonical pasteboard after the real canvas has a usable size.
    @MainActor
    func testFreshWorkspaceFitsPasteboardWithoutMutatingAuthoredCoordinates() throws {
        let state = WorkspaceShellState()
        let document = state.documentSession.document
        state.resizeViewport(to: .init(width: 1_000, height: 700), pixelRatio: 2)

        XCTAssertEqual(state.viewportState.fitPolicy, .none)
        let origin = try state.viewportState.transform.worldToViewport(
            state.viewportState.contentBounds.origin
        )
        let width = state.viewportState.contentBounds.size.width * state.viewportState.zoom.value
        let height = state.viewportState.contentBounds.size.height * state.viewportState.zoom.value
        XCTAssertEqual(origin.x + width / 2, state.viewportState.viewportSize.width / 2, accuracy: 0.000_001)
        XCTAssertEqual(origin.y + height / 2, state.viewportState.viewportSize.height / 2, accuracy: 0.000_001)
        XCTAssertEqual(state.documentSession.document, document)
    }

    // SF-0401-001, SF-0401-004, SF-0401-008
    func testWorldViewportDeviceRoundTripsAcrossRepresentativeScales() throws {
        for scale in [1.0, 1.5, 2.0, 3.0, 4.0] {
            let transform = try CanvasCoordinateTransform(
                worldOrigin: WorldPoint(x: -98_765.4321, y: 45_678.9876),
                zoom: CanvasZoom(3.125),
                pixelRatio: CanvasPixelRatio(scale)
            )
            for point in [
                WorldPoint(x: -999_999.25, y: -0.125),
                WorldPoint(x: 0, y: 0),
                WorldPoint(x: 847_293_011.75, y: -125_000_000.5),
            ] {
                let viewport = try transform.worldToViewport(point)
                let world = try transform.viewportToWorld(viewport)
                XCTAssertEqual(world.x, point.x, accuracy: CanvasCoordinateTransform.reversibleTolerance)
                XCTAssertEqual(world.y, point.y, accuracy: CanvasCoordinateTransform.reversibleTolerance)
                let device = try transform.worldToDevice(point)
                let fromDevice = try transform.deviceToWorld(device)
                XCTAssertEqual(fromDevice.x, point.x, accuracy: CanvasCoordinateTransform.reversibleTolerance)
                XCTAssertEqual(fromDevice.y, point.y, accuracy: CanvasCoordinateTransform.reversibleTolerance)
            }
        }
    }

    // SF-0401-001, SF-0401-004
    func testInvalidNonfiniteOverflowSizeZoomAndPixelRatioAreRejected() throws {
        XCTAssertThrowsError(try CanvasZoom(.nan))
        XCTAssertThrowsError(try CanvasZoom(0.1))
        XCTAssertThrowsError(try CanvasPixelRatio(0))
        XCTAssertThrowsError(try CanvasPixelRatio(.infinity))
        XCTAssertThrowsError(try CanvasCoordinateTransform(
            worldOrigin: WorldPoint(x: 1e13, y: 0),
            zoom: .actualSize,
            pixelRatio: CanvasPixelRatio(2)
        ))
        XCTAssertThrowsError(try CanvasViewportState(
            viewportSize: ViewportSize(width: 0, height: 700)
        ))
        let transform = try CanvasCoordinateTransform(
            worldOrigin: WorldPoint(x: 0, y: 0),
            zoom: .actualSize,
            pixelRatio: CanvasPixelRatio(2)
        )
        XCTAssertThrowsError(try transform.worldToViewport(WorldPoint(x: .nan, y: 0)))
    }

    // SF-0401-001, SF-0401-002, SF-0401-005
    func testCursorAnchoredZoomClampsAtMinimumNormalAndMaximum() throws {
        var state = try CanvasViewportState(worldOrigin: WorldPoint(x: -400, y: 250))
        let cursor = ViewportPoint(x: 317.25, y: 211.75)
        let anchor = try state.transform.viewportToWorld(cursor)

        try state.zoom(to: 2.75, around: cursor)
        assertWorld(try state.transform.viewportToWorld(cursor), equals: anchor)
        try state.zoom(to: 0.001, around: cursor)
        XCTAssertEqual(state.zoom, .minimum)
        assertWorld(try state.transform.viewportToWorld(cursor), equals: anchor)
        try state.zoom(to: 100, around: cursor)
        XCTAssertEqual(state.zoom, .maximum)
        assertWorld(try state.transform.viewportToWorld(cursor), equals: anchor)
    }

    // SF-0401-002, SF-0401-003, SF-0401-004
    func testPanBoundsResizeResetAndFitPoliciesAreDeterministic() throws {
        var state = try CanvasViewportState(
            viewportSize: ViewportSize(width: 800, height: 600),
            contentBounds: WorldRect(
                origin: WorldPoint(x: -1_000, y: -500),
                size: WorldSize(width: 2_000, height: 1_000)
            )
        )
        let center = try state.transform.viewportToWorld(ViewportPoint(x: 400, y: 300))
        try state.resize(to: ViewportSize(width: 1_000, height: 700), pixelRatio: 1.5)
        assertWorld(try state.transform.viewportToWorld(ViewportPoint(x: 500, y: 350)), equals: center)

        try state.pan(by: ViewportVector(dx: 1e9, dy: -1e9))
        XCTAssertGreaterThanOrEqual(state.worldOrigin.x, state.contentBounds.minX - CanvasViewportState.panPadding)
        XCTAssertLessThanOrEqual(state.visibleWorldRect.maxY, state.contentBounds.maxY + CanvasViewportState.panPadding + 1e-9)

        try state.fit(.fitDocument)
        XCTAssertEqual(state.fitPolicy, .fitDocument)
        XCTAssertLessThanOrEqual(state.visibleWorldRect.minX, state.contentBounds.minX)
        XCTAssertGreaterThanOrEqual(state.visibleWorldRect.maxX, state.contentBounds.maxX)
        try state.fit(.fitWidth)
        XCTAssertEqual(state.fitPolicy, .fitWidth)
        XCTAssertEqual(
            state.contentBounds.size.width * state.zoom.value,
            state.viewportSize.width - 96,
            accuracy: 1e-8
        )
        try state.reset()
        XCTAssertEqual(state.zoom, .actualSize)
        XCTAssertEqual(state.fitPolicy, .none)
    }

    // SF-0401-001, SF-0401-007
    func testRepeatedConversionsDoNotAccumulateDrift() throws {
        let transform = try CanvasCoordinateTransform(
            worldOrigin: WorldPoint(x: -123_456.789, y: 987_654.321),
            zoom: CanvasZoom(7.875),
            pixelRatio: CanvasPixelRatio(2)
        )
        let original = WorldPoint(x: -42_424.2424, y: 81_818.1818)
        var value = original
        for _ in 0..<10_000 {
            value = try transform.deviceToWorld(transform.worldToDevice(value))
        }
        assertWorld(value, equals: original)
        let aligned = try transform.pixelAligned(ViewportPoint(x: 10.26, y: 20.74))
        XCTAssertEqual(aligned.x * 2, (10.26 * 2).rounded(.toNearestOrEven))
        XCTAssertEqual(aligned.y * 2, (20.74 * 2).rounded(.toNearestOrEven))
    }

    // SF-0401-004, SF-0401-007, SF-0401-008
    func testPreparationCancellationAndStaleIdentityAreStateNeutral() async throws {
        let document = ProjectCreation.blank()
        let state = try CanvasViewportState()
        let identity = CanvasViewportOperationIdentity(
            documentID: document.id,
            revision: document.revision,
            sceneID: state.sceneID,
            generation: state.generation
        )
        let objects = fixtureObjects(count: 10_000)
        let request = CanvasViewportPreparationRequest(identity: identity, viewport: state, objects: objects)
        let preparer = CanvasViewportScenePreparer()
        let counter = CancellationCounter()
        do {
            _ = try await preparer.prepare(request, cancellation: CanvasViewportCancellation {
                counter.incrementAndReached(4)
            })
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? CanvasViewportError, .cancelled)
        }

        let valid = try await preparer.prepare(request)
        let stale = CanvasViewportOperationIdentity(
            documentID: identity.documentID,
            revision: identity.revision + 1,
            sceneID: identity.sceneID,
            generation: identity.generation
        )
        XCTAssertThrowsError(try CanvasViewportAdoptionGate().validate(valid, expected: stale)) {
            XCTAssertEqual($0 as? CanvasViewportError, .staleResult)
        }
    }

    // SF-0401-007, SF-0401-008
    @MainActor
    func testHundredAndTenThousandObjectPreparationIsDeterministicAndYieldsMainActor() async throws {
        let context = WorkspaceDocumentContext()
        var mainActorProgressed = false
        let marker = Task { @MainActor in
            await Task.yield()
            mainActorProgressed = true
        }
        let hundred = try await context.shellState.prepareViewportScene(objects: fixtureObjects(count: 100))
        let tenThousand = try await context.shellState.prepareViewportScene(objects: fixtureObjects(count: 10_000))
        _ = await marker.value
        XCTAssertTrue(mainActorProgressed)
        XCTAssertEqual(hundred.objectCount, 100)
        XCTAssertEqual(tenThousand.objectCount, 10_000)
        let repeatResult = try await context.shellState.prepareViewportScene(objects: fixtureObjects(count: 10_000))
        XCTAssertEqual(repeatResult.deterministicDigest, tenThousand.deterministicDigest)
    }

    // SF-0401-001, SF-0401-005, SF-0401-008
    @MainActor
    func testViewportIsIndependentPerWindowAndNeverMutatesCanonicalDocument() throws {
        let first = WorkspaceDocumentContext()
        let second = WorkspaceDocumentContext()
        let firstDocument = first.shellState.documentSession.document
        let secondDocument = second.shellState.documentSession.document
        first.shellState.performViewportCommand(CanvasViewportCommand(.zoomIn))
        first.shellState.performViewportCommand(CanvasViewportCommand(.panRight))

        XCTAssertNotEqual(first.shellState.viewportState, second.shellState.viewportState)
        XCTAssertEqual(first.shellState.documentSession.document, firstDocument)
        XCTAssertEqual(second.shellState.documentSession.document, secondDocument)
        XCTAssertEqual(second.shellState.zoomPercent, 100)
        XCTAssertNotEqual(first.shellState.viewportState.sceneID, second.shellState.viewportState.sceneID)
    }

    // SF-0401-004, SF-0401-005, SF-0401-008
    @MainActor
    func testOperationIdentityTracksDocumentRevisionSceneAndViewportGeneration() async throws {
        let state = WorkspaceShellState()
        let initial = state.currentViewportOperationIdentity

        state.performViewportCommand(CanvasViewportCommand(.zoomIn))
        let zoomed = state.currentViewportOperationIdentity
        XCTAssertEqual(zoomed.documentID, initial.documentID)
        XCTAssertEqual(zoomed.revision, initial.revision)
        XCTAssertEqual(zoomed.sceneID, initial.sceneID)
        XCTAssertGreaterThan(zoomed.generation, initial.generation)

        let replacement = ProjectCreation.blank()
        try state.documentSession.establishBaseline(replacement)
        await Task.yield()
        await Task.yield()
        let adopted = state.currentViewportOperationIdentity
        XCTAssertEqual(adopted.documentID, replacement.id)
        XCTAssertEqual(adopted.revision, replacement.revision)
        XCTAssertNotEqual(adopted.sceneID, initial.sceneID)
        XCTAssertEqual(adopted.generation, 0)
    }

    // SF-0401-006, SF-0401-008
    @MainActor
    func testCentralViewportCommandsAnnounceAndDiagnosticsRemainRedacted() async {
        var announcements: [String] = []
        let diagnostics = CanvasViewportDiagnostics()
        let state = WorkspaceShellState(
            viewportDiagnostics: diagnostics,
            announcementPoster: AccessibilityAnnouncementPoster { announcements.append($0) }
        )
        state.performViewportCommand(CanvasViewportCommand(.zoomIn))
        state.performViewportCommand(CanvasViewportCommand(.panLeft))
        await Task.yield()

        XCTAssertEqual(announcements, ["Canvas zoom 125 percent", "Canvas panned panLeft"])
        let records = await diagnostics.snapshot()
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.requirementID == "SF-0401-008" })
        XCTAssertTrue(records.allSatisfy { $0.sceneIdentifier.count == 8 })
        let encoded = String(data: try! JSONEncoder().encode(records), encoding: .utf8)!
        XCTAssertFalse(encoded.contains(state.documentSession.document.id.description))
        XCTAssertFalse(encoded.contains("/Users/"))
    }

    // SF-0401-006, SF-0401-008
    func testViewportCommandRegistryDefinesIntentionalEnablement() throws {
        let registry = CanvasViewportCommandRegistry()
        var state = try CanvasViewportState()
        XCTAssertTrue(registry.isEnabled(CanvasViewportCommand(.zoomIn), in: state))
        try state.zoom(to: CanvasZoom.maximum.value, around: ViewportPoint(x: 0, y: 0))
        XCTAssertFalse(registry.isEnabled(CanvasViewportCommand(.zoomIn), in: state))
        XCTAssertThrowsError(try registry.apply(CanvasViewportCommand(.zoomIn), to: &state))
        XCTAssertTrue(registry.isEnabled(CanvasViewportCommand(.actualSize), in: state))
    }

    private func fixtureObjects(count: Int) -> [CanvasViewportSceneObject] {
        (0..<count).map { index in
            let uuid = UUID(uuidString: String(
                format: "51000000-0000-0000-0000-%012llx",
                UInt64(index + 1)
            ))!
            return CanvasViewportSceneObject(
                id: NodeID(uuid),
                bounds: WorldRect(
                    origin: WorldPoint(x: Double(index % 100) * 120 - 4_000, y: Double(index / 100) * 80 - 2_000),
                    size: WorldSize(width: 100, height: 60)
                )
            )
        }
    }

    private func assertWorld(
        _ actual: WorldPoint,
        equals expected: WorldPoint,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: CanvasCoordinateTransform.reversibleTolerance, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: CanvasCoordinateTransform.reversibleTolerance, file: file, line: line)
    }
}

private final class CancellationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func incrementAndReached(_ limit: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value >= limit
    }
}
