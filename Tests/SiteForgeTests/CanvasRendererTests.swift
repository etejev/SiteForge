import XCTest
@testable import SiteForge

final class CanvasRendererTests: XCTestCase {
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
            case .frame, .text, .image, .button, .link, .component: []
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
