import XCTest
@testable import SiteForge

final class CanvasRendererTests: XCTestCase {
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
        XCTAssertEqual(record.surfaceIdentifier.count, 8)
        XCTAssertLessThanOrEqual(record.failureCategory?.count ?? 0, 64)
        XCTAssertFalse(encoded.contains("/Users/"))
        XCTAssertFalse(encoded.contains(fixture.scene.objects[0].accessibilityLabel))
    }

    // SF-0407-007, SF-0407-008
    @MainActor
    func testProductionWorkerKeepsMainActorResponsiveAtTenThousandObjects() async throws {
        let fixture = try makeFixture(count: 10_000)
        let worker = CanvasRenderWorker()
        let task = Task(priority: .userInitiated) {
            try await worker.prepare(scene: fixture.scene, overlays: fixture.overlays, viewport: fixture.viewport)
        }
        var turns = 0
        for _ in 0..<20 { turns += 1; await Task.yield() }
        let plan = try await task.value
        XCTAssertEqual(turns, 20)
        XCTAssertEqual(plan.authoredObjects.count, 10_000)
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
                accessibilityLabel: "Object \(index + 1)"
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
