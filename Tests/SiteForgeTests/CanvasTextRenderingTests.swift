import AppKit
import XCTest
@testable import SiteForge

@MainActor
final class CanvasTextRenderingTests: XCTestCase {
    // SF-0405-006, SF-0406-001, SF-0406-002, SF-0406-005 — structural names
    // are tile-rasterized. Plain text intentionally composes in its own
    // non-tiled authored subtree, covered by the shared layout and app tests.
    func testNativeTileFrameNamePixelsStayWithinItsAuthoredFrame() throws {
        let viewport = try CanvasViewportState(
            worldOrigin: .init(x: 0, y: 0),
            viewportSize: .init(width: 300, height: 120),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 300, height: 120)),
            pixelRatio: CanvasPixelRatio(2)
        )
        let base = CanvasRenderObject(
            id: NodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000201")!),
            frame: .init(origin: .init(x: 32, y: 24), size: .init(width: 180, height: 42)),
            clipRect: .init(origin: .init(x: 0, y: 0), size: .init(width: 300, height: 120)),
            paintOrder: 0,
            style: .textPlaceholder,
            isVisible: true,
            accessibilityLabel: "Text object"
        )
        let namedFrame = CanvasRenderObject(
            id: NodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000202")!),
            frame: base.frame,
            clipRect: base.clipRect,
            paintOrder: 0,
            style: .frameSurface,
            isVisible: true,
            accessibilityLabel: "Frame object",
            displayName: "Frame"
        )
        let unnamedFrame = CanvasRenderObject(
            id: namedFrame.id,
            frame: namedFrame.frame,
            clipRect: namedFrame.clipRect,
            paintOrder: namedFrame.paintOrder,
            style: namedFrame.style,
            isVisible: namedFrame.isVisible,
            accessibilityLabel: namedFrame.accessibilityLabel
        )
        let frameLabelPixels = changedPixels(
            from: rasterizedBytes(object: unnamedFrame, viewport: viewport),
            to: rasterizedBytes(object: namedFrame, viewport: viewport),
            width: 300
        )
        XCTAssertFalse(frameLabelPixels.isEmpty)
        XCTAssertTrue(
            frameLabelPixels.allSatisfy { (32..<212).contains($0.x) && (16..<74).contains($0.y) },
            "Frame-name pixels escaped the authored frame: \(pixelBounds(frameLabelPixels))"
        )
    }

    // SF-0401-001, SF-0401-004, SF-0402-006, SF-0405-006, SF-0406-001 —
    // the shared AppKit/Core Graphics tile boundary performs exactly one
    // reversible Y conversion across canonical viewport values.
    func testFrameAndTextUseOneUprightTopLeftTileConventionAcrossViewportMatrix() throws {
        let tileBounds = CGRect(x: 0, y: 0, width: 320, height: 240)
        for zoom in [CanvasZoom.minimum, .actualSize, CanvasZoom.maximum] {
            for pixelRatio in [try CanvasPixelRatio(1), try CanvasPixelRatio(2)] {
                for worldOrigin in [WorldPoint(x: -32, y: -24), WorldPoint(x: 20, y: 16)] {
                    let transform = try CanvasCoordinateTransform(
                        worldOrigin: worldOrigin,
                        zoom: zoom,
                        pixelRatio: pixelRatio
                    )
                    let canonicalOrigin = WorldPoint(x: worldOrigin.x + 16, y: worldOrigin.y + 14)
                    let viewportOrigin = try transform.worldToViewport(canonicalOrigin)
                    let canonicalRect = CGRect(
                        x: viewportOrigin.x,
                        y: viewportOrigin.y,
                        width: 40 * zoom.value,
                        height: 28 * zoom.value
                    )
                    let rasterRect = CanvasTileTextCoordinateSpace.drawingRect(for: canonicalRect, in: tileBounds)
                    XCTAssertEqual(rasterRect.minX, canonicalRect.minX, accuracy: 0.000_001)
                    XCTAssertEqual(rasterRect.height, canonicalRect.height, accuracy: 0.000_001)
                    XCTAssertTrue(abs((rasterRect.minY + canonicalRect.maxY) - tileBounds.height) < 0.000_001)
                    XCTAssertEqual(try transform.viewportToWorld(viewportOrigin), canonicalOrigin)
                }
            }
        }
    }

    // SF-0401-001, SF-0405-006, SF-0406-001, SF-0406-002 — the committed
    // tile and native inline editor share one rect/inset/baseline contract.
    func testSharedTextLayoutKeepsGlyphsInsideOneViewportRectAcrossMatrix() throws {
        let text = "Canvas text"
        for zoom in [CanvasZoom.minimum.value, 1.0, CanvasZoom.maximum.value] {
            for pixelRatio in [try CanvasPixelRatio(1), try CanvasPixelRatio(2)] {
                for origin in [WorldPoint(x: -512, y: -256), WorldPoint(x: 384, y: 192)] {
                    let transform = try CanvasCoordinateTransform(
                        worldOrigin: origin,
                        zoom: try CanvasZoom(zoom),
                        pixelRatio: pixelRatio
                    )
                    let worldFrame = WorldRect(
                        origin: .init(x: origin.x + 128, y: origin.y + 96),
                        size: .init(width: 240, height: 48)
                    )
                    let viewportOrigin = try transform.worldToViewport(worldFrame.origin)
                    let objectRect = CGRect(
                        x: viewportOrigin.x,
                        y: viewportOrigin.y,
                        width: worldFrame.size.width * zoom,
                        height: worldFrame.size.height * zoom
                    )
                    let layout = CanvasTextLayout(
                        viewportObjectRect: objectRect,
                        zoom: zoom,
                        text: text
                    )
                    let tolerance = 1 / pixelRatio.value
                    XCTAssertEqual(layout.viewportObjectRect, objectRect)
                    XCTAssertGreaterThanOrEqual(layout.glyphBounds.minX + tolerance, objectRect.minX)
                    XCTAssertLessThanOrEqual(layout.glyphBounds.maxX - tolerance, objectRect.maxX)
                    XCTAssertGreaterThanOrEqual(layout.glyphBounds.minY + tolerance, objectRect.minY)
                    XCTAssertLessThanOrEqual(layout.glyphBounds.maxY - tolerance, objectRect.maxY)
                    XCTAssertEqual(
                        layout.glyphBounds.midY,
                        objectRect.midY,
                        accuracy: tolerance,
                        "glyph baseline drifted at zoom \(zoom), scale \(pixelRatio.value)"
                    )
                    let tileRect = CanvasTileTextCoordinateSpace.drawingRect(
                        for: layout.lineFragmentRect,
                        in: CGRect(x: 0, y: 0, width: 512, height: 512)
                    )
                    XCTAssertEqual(tileRect.height, layout.lineFragmentRect.height, accuracy: 0.000_001)
                }
            }
        }
    }

    // SF-0406-001, SF-0406-002, SF-0508-005 — committed plain-text glyphs
    // use the production CATextLayer path and inherit authored object opacity
    // exactly like the tiled surface (including fully transparent text).
    func testProductionAuthoredTextLayerPixelsHonorObjectOpacity() throws {
        let width = 240
        let height = 100
        let viewport = try CanvasViewportState(
            worldOrigin: .init(x: 0, y: 0),
            viewportSize: .init(width: Double(width), height: Double(height)),
            contentBounds: .init(
                origin: .init(x: 0, y: 0),
                size: .init(width: Double(width), height: Double(height))
            ),
            pixelRatio: CanvasPixelRatio(2)
        )
        let frame = WorldRect(
            origin: .init(x: 20, y: 20),
            size: .init(width: 180, height: 40)
        )

        var maximumAlpha: [Double: UInt8] = [:]
        for opacity in [1.0, 0.5, 0.0] {
            let object = CanvasRenderObject(
                id: NodeID(),
                frame: frame,
                clipRect: nil,
                paintOrder: 0,
                style: .textPlaceholder,
                isVisible: true,
                accessibilityLabel: "Opacity text",
                plainText: "SiteForge opacity",
                opacity: opacity
            )
            let layer = try XCTUnwrap(CanvasAuthoredTextLayerFactory.makeLayer(
                for: object,
                viewport: viewport,
                contentsScale: 2
            ))
            XCTAssertEqual(layer.opacity, Float(opacity), accuracy: 0.000_001)
            let pixels = rasterizedTextLayerBytes(layer, width: width, height: height)
            maximumAlpha[opacity] = stride(from: 3, to: pixels.count, by: 4)
                .map { pixels[$0] }
                .max() ?? 0
            let changed = changedPixels(
                from: Data(repeating: 0, count: pixels.count),
                to: pixels,
                width: width
            )
            if opacity == 0 {
                XCTAssertTrue(changed.isEmpty, "Zero-opacity authored text must paint no glyph pixels.")
            } else {
                XCTAssertFalse(changed.isEmpty)
                XCTAssertTrue(
                    changed.allSatisfy { layer.frame.insetBy(dx: -1, dy: -1).contains(CGPoint(x: $0.x, y: $0.y)) },
                    "Authored text pixels escaped the production CATextLayer bounds: \(pixelBounds(changed))"
                )
            }
        }

        let opaque = try XCTUnwrap(maximumAlpha[1.0])
        let half = try XCTUnwrap(maximumAlpha[0.5])
        XCTAssertGreaterThan(opaque, 0)
        XCTAssertEqual(Double(half) / Double(opaque), 0.5, accuracy: 0.08)
        XCTAssertEqual(maximumAlpha[0.0], 0)
    }

    // SF-0508-001...005, SF-0508-008 — authored RGBA/opacity is composited
    // by the production tile layer. Editor overlays are a different scene and
    // cannot affect these raw authored pixels.
    func testAuthoredSolidFillAndOpacityUseExactTilePixelsWithoutEditorOverlayContamination() throws {
        let authored = [32.0 / 255.0, 64.0 / 255.0, 96.0 / 255.0, 1.0]
        for zoom in [CanvasZoom.minimum, .actualSize, CanvasZoom.maximum] {
            for pixelRatio in [try CanvasPixelRatio(1), try CanvasPixelRatio(2)] {
                for origin in [WorldPoint(x: -256, y: 192), WorldPoint(x: 320, y: -224)] {
                    let viewport = try CanvasViewportState(
                        worldOrigin: origin,
                        viewportSize: .init(width: 300, height: 120),
                        contentBounds: .init(origin: .init(x: -2_000, y: -2_000), size: .init(width: 8_000, height: 8_000)),
                        zoom: zoom,
                        pixelRatio: pixelRatio
                    )
                    // Keep the sample interior in the finite test bitmap at
                    // every zoom while retaining a different canonical frame
                    // for each transform. This also puts the tile's local
                    // origin inside the object rather than testing a
                    // screen-fixed rectangle.
                    let worldFrame = WorldRect(
                        origin: .init(x: origin.x + 96 / zoom.value, y: origin.y + 48 / zoom.value),
                        size: .init(width: 80 / zoom.value, height: 48 / zoom.value)
                    )
                    let viewportOrigin = try viewport.transform.worldToViewport(worldFrame.origin)
                    // `CALayer.render(in:)` writes its bitmap scanlines in
                    // Core Graphics' bottom-left orientation. Convert the
                    // authored top-left viewport centre once at the test
                    // image boundary; the production tile itself remains
                    // entirely top-left/Y-down.
                    let center = (
                        x: Int((viewportOrigin.x + worldFrame.size.width * zoom.value / 2).rounded()),
                        y: Int((Double(120) - viewportOrigin.y - worldFrame.size.height * zoom.value / 2).rounded())
                    )
                    let expectedBitmapRect = CGRect(
                        x: viewportOrigin.x,
                        y: Double(120) - viewportOrigin.y - worldFrame.size.height * zoom.value,
                        width: worldFrame.size.width * zoom.value,
                        height: worldFrame.size.height * zoom.value
                    )
                    for (opacity, expectedAlpha) in [(1.0, 255), (0.5, 128), (0.0, 0)] {
                        autoreleasepool {
                        let object = CanvasRenderObject(
                            id: NodeID(), frame: worldFrame, clipRect: nil, paintOrder: 0,
                            style: .frameSurface, isVisible: true, accessibilityLabel: "Frame",
                            fillRGBA: authored, opacity: opacity
                        )
                        let pixels = rasterizedBytes(object: object, viewport: viewport)
                        let inside = rgba(at: center, in: pixels, width: 300, height: 120)
                        let hidden = CanvasRenderObject(
                            id: object.id, frame: object.frame, clipRect: object.clipRect,
                            paintOrder: object.paintOrder, style: object.style,
                            isVisible: false, accessibilityLabel: object.accessibilityLabel,
                            fillRGBA: object.fillRGBA, opacity: object.opacity
                        )
                        let changed = changedPixels(
                            from: rasterizedBytes(object: hidden, viewport: viewport),
                            to: pixels, width: 300
                        )
                        if opacity == 0 {
                            XCTAssertTrue(changed.isEmpty, "A zero-opacity authored fill must not paint any pixel.")
                        } else {
                            XCTAssertFalse(changed.isEmpty)
                            XCTAssertTrue(
                                changed.allSatisfy {
                                    expectedBitmapRect.insetBy(dx: -1, dy: -1).contains(
                                        CGPoint(x: $0.x, y: $0.y)
                                    )
                                },
                                "The production tile painted outside its exact resolved object bounds: \(pixelBounds(changed)) expected \(expectedBitmapRect)"
                            )
                        }
                        XCTAssertEqual(Int(inside.alpha), expectedAlpha, accuracy: 3, "alpha at zoom \(zoom.value), scale \(pixelRatio.value), origin \(origin), center \(center), changed \(pixelBounds(changed))")
                        // The production renderer resolves calibrated input
                        // into the active device RGB target. Test that target
                        // directly: alpha is exact and the normalized 1:2:3
                        // channel relationship survives premultiplication
                        // within the compositor's three-byte tolerance.
                        if opacity > 0 {
                            XCTAssertGreaterThan(inside.red, 0)
                            XCTAssertEqual(Double(inside.green) / Double(inside.red), 2, accuracy: 0.10)
                            // At 50% alpha, 8-bit premultiplication rounds
                            // the smallest red channel before the other two.
                            // A quarter-ratio tolerance is therefore the
                            // explicit device-pixel policy, not a broad
                            // changed-pixel assertion.
                            XCTAssertEqual(Double(inside.blue) / Double(inside.red), 3, accuracy: 0.25)
                        } else {
                            XCTAssertEqual(inside.red, 0)
                            XCTAssertEqual(inside.green, 0)
                            XCTAssertEqual(inside.blue, 0)
                        }
                        let outside = rgba(at: (x: 4, y: 4), in: pixels, width: 300, height: 120)
                        XCTAssertEqual(outside.red, 0, "Authoring fill must not paint outside the exact object bounds.")
                        XCTAssertEqual(outside.green, 0)
                        XCTAssertEqual(outside.blue, 0)
                        XCTAssertEqual(outside.alpha, 0)
                        }
                    }
                }
            }
        }
    }

    // SF-0508-001, SF-0508-003, SF-0508-005, SF-0508-008 — the production
    // tile rasterizes the immutable authored layer order, ignores disabled
    // layers, and applies object opacity once after source-over compositing.
    func testAuthoredFillLayerStackAndGradientUseExactProductionTilePixels() throws {
        let viewport = try CanvasViewportState(
            worldOrigin: .init(x: 0, y: 0),
            viewportSize: .init(width: 300, height: 120),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 300, height: 120)),
            pixelRatio: CanvasPixelRatio(2)
        )
        let frame = WorldRect(
            origin: .init(x: 40, y: 30),
            size: .init(width: 160, height: 60)
        )
        let clip = WorldRect(
            origin: .init(x: 0, y: 0),
            size: .init(width: 300, height: 120)
        )
        func solid(_ uuid: String, _ rgba: [Double], enabled: Bool = true) -> CanvasAuthoredFillLayer {
            CanvasAuthoredFillLayer(
                id: UUID(uuidString: uuid)!, kind: .solid,
                isEnabled: enabled, rgba: rgba, angleDegrees: nil, stops: []
            )
        }

        let layered = CanvasRenderObject(
            id: NodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000301")!),
            frame: frame, clipRect: clip, paintOrder: 0,
            style: .frameSurface, isVisible: true, accessibilityLabel: "Layered frame",
            fillLayers: [
                solid("00000000-0000-0000-0000-000000000302", [1, 0, 0, 1]),
                solid("00000000-0000-0000-0000-000000000303", [0, 1, 0, 1], enabled: false),
                solid("00000000-0000-0000-0000-000000000304", [0, 0, 1, 0.5]),
            ],
            opacity: 0.5
        )
        let layeredPixels = rasterizedBytes(object: layered, viewport: viewport)
        let layeredCenter = rgba(at: (x: 120, y: 60), in: layeredPixels, width: 300, height: 120)
        let withoutDisabledLayer = CanvasRenderObject(
            id: NodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000309")!),
            frame: frame, clipRect: clip, paintOrder: 0,
            style: .frameSurface, isVisible: true, accessibilityLabel: "Reference layered frame",
            fillLayers: [
                solid("00000000-0000-0000-0000-000000000310", [1, 0, 0, 1]),
                solid("00000000-0000-0000-0000-000000000311", [0, 0, 1, 0.5]),
            ],
            opacity: 0.5
        )
        let referencePixels = rasterizedBytes(object: withoutDisabledLayer, viewport: viewport)
        let referenceCenter = rgba(at: (x: 120, y: 60), in: referencePixels, width: 300, height: 120)
        XCTAssertEqual(
            [layeredCenter.red, layeredCenter.green, layeredCenter.blue, layeredCenter.alpha],
            [referenceCenter.red, referenceCenter.green, referenceCenter.blue, referenceCenter.alpha],
            "A disabled fill layer must have no effect on the production raster."
        )
        XCTAssertEqual(Int(layeredCenter.red), 64, accuracy: 4)
        XCTAssertEqual(Int(layeredCenter.blue), 64, accuracy: 4)
        XCTAssertEqual(Int(layeredCenter.alpha), 128, accuracy: 3, "Object opacity must apply once to the completed opaque layer stack.")
        let layeredOutside = rgba(at: (x: 20, y: 60), in: layeredPixels, width: 300, height: 120)
        XCTAssertEqual(layeredOutside.alpha, 0, "Pixels outside the authored object bounds must remain transparent.")

        let gradient = CanvasAuthoredFillLayer(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000305")!,
            kind: .linearGradient,
            isEnabled: true,
            rgba: nil,
            angleDegrees: 0,
            stops: [
                .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000306")!, position: 0, rgba: [1, 0, 0, 1]),
                .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000307")!, position: 1, rgba: [0, 0, 1, 1]),
            ]
        )
        let gradientObject = CanvasRenderObject(
            id: NodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000308")!),
            frame: frame, clipRect: clip, paintOrder: 0,
            style: .frameSurface, isVisible: true, accessibilityLabel: "Gradient frame",
            fillLayers: [gradient]
        )
        let gradientPixels = rasterizedBytes(object: gradientObject, viewport: viewport)
        let left = rgba(at: (x: 60, y: 60), in: gradientPixels, width: 300, height: 120)
        let center = rgba(at: (x: 120, y: 60), in: gradientPixels, width: 300, height: 120)
        let right = rgba(at: (x: 180, y: 60), in: gradientPixels, width: 300, height: 120)
        XCTAssertEqual(Int(left.red), 223, accuracy: 4)
        XCTAssertEqual(Int(left.blue), 32, accuracy: 4)
        XCTAssertEqual(Int(center.red), 127, accuracy: 4)
        XCTAssertEqual(Int(center.blue), 128, accuracy: 4)
        XCTAssertEqual(Int(right.red), 32, accuracy: 4)
        XCTAssertEqual(Int(right.blue), 223, accuracy: 4)
        for sample in [left, center, right] {
            XCTAssertEqual(Int(sample.alpha), 255, accuracy: 3)
        }
        let gradientOutside = rgba(at: (x: 220, y: 60), in: gradientPixels, width: 300, height: 120)
        XCTAssertEqual(gradientOutside.alpha, 0, "Pixels outside the authored object bounds must remain transparent.")
    }

    // SF-0506-003/005/008 — production raster composition is shadow, rounded
    // clipped fill, then authored border. Editor overlays are not in this tile.
    func testBorderRadiusAndShadowUseProductionTileCompositionWithoutGeometryDrift() throws {
        let viewport = try CanvasViewportState(
            worldOrigin: .init(x: 0, y: 0), viewportSize: .init(width: 300, height: 120),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 300, height: 120)),
            pixelRatio: .init(2)
        )
        let frame = WorldRect(origin: .init(x: 60, y: 24), size: .init(width: 120, height: 64))
        let object = CanvasRenderObject(
            id: NodeID(), frame: frame, clipRect: viewport.contentBounds, paintOrder: 0,
            style: .frameSurface, isVisible: true, accessibilityLabel: "Styled frame",
            fillRGBA: [0.9, 0.9, 0.95, 1],
            border: .init(rgba: [0.1, 0.2, 0.8, 1], width: 4, style: .solid),
            cornerRadius: 16,
            shadow: .init(rgba: [0, 0, 0, 0.35], offsetX: 0, offsetY: 8, blur: 8, spread: 1)
        )
        let pixels = rasterizedBytes(object: object, viewport: viewport)
        let center = rgba(at: (x: 120, y: 64), in: pixels, width: 300, height: 120)
        XCTAssertGreaterThan(center.alpha, 240, "Rounded clipping must retain the authored centre fill.")
        let border = rgba(at: (x: 62, y: 60), in: pixels, width: 300, height: 120)
        XCTAssertGreaterThan(border.blue, border.red, "The authored blue border must win at the edge.")
        let roundedCorner = rgba(at: (x: 60, y: 96), in: pixels, width: 300, height: 120)
        XCTAssertLessThan(roundedCorner.alpha, center.alpha, "Uniform radius must clip the object corner.")
        let withoutShadow = CanvasRenderObject(
            id: object.id, frame: object.frame, clipRect: object.clipRect, paintOrder: object.paintOrder,
            style: object.style, isVisible: true, accessibilityLabel: object.accessibilityLabel,
            fillRGBA: object.fillRGBA, opacity: object.opacity, border: object.border,
            cornerRadius: object.cornerRadius
        )
        let shadowOnlyPixels = changedPixels(
            from: rasterizedBytes(object: withoutShadow, viewport: viewport),
            to: pixels, width: 300
        )
        let objectBitmapRect = CGRect(x: 60, y: 120 - 24 - 64, width: 120, height: 64)
        XCTAssertTrue(
            shadowOnlyPixels.contains { !objectBitmapRect.contains(CGPoint(x: $0.x, y: $0.y)) },
            "The production shadow must paint beyond the authored object without changing its frame."
        )
        XCTAssertEqual(object.frame, frame)
    }

    private func rasterizedBytes(object: CanvasRenderObject, viewport: CanvasViewportState) -> Data {
        let width = 300
        let height = 120
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { rawBuffer in
            let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            // Render through the same flipped layer composition used by the
            // native viewport. Calling tile.draw(in:) directly bypasses
            // CALayer's geometry transform and cannot prove text/clip parity.
            let root = CALayer()
            root.frame = CGRect(x: 0, y: 0, width: width, height: height)
            // `NativeCanvasViewportView` is an `NSView.isFlipped` host. Its
            // root layer therefore establishes the same top-left coordinate
            // space as every owned canvas subtree before tiles are added.
            root.isGeometryFlipped = true
            let container = CALayer()
            container.frame = root.bounds
            container.isGeometryFlipped = true
            root.addSublayer(container)
            let layer = CanvasContentTileLayer()
            // A nonzero tile origin proves the explicit flipped container
            // keeps tile placement and tile-local text/clipping coordinates
            // in the same authored viewport space.
            layer.frame = CGRect(x: 8, y: 12, width: width - 8, height: height - 12)
            layer.contentsScale = 1
            layer.viewportState = viewport
            layer.objects = [object]
            layer.tileOrigin = layer.frame.origin
            container.addSublayer(layer)
            layer.setNeedsDisplay()
            root.render(in: context)
        }
        return Data(bytes)
    }

    private func rasterizedTextLayerBytes(_ textLayer: CATextLayer, width: Int, height: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { rawBuffer in
            let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let root = CALayer()
            root.frame = CGRect(x: 0, y: 0, width: width, height: height)
            root.isGeometryFlipped = true
            root.addSublayer(textLayer)
            textLayer.setNeedsDisplay()
            root.render(in: context)
        }
        return Data(bytes)
    }

    private func changedPixels(from lhs: Data, to rhs: Data, width: Int) -> [(x: Int, y: Int)] {
        precondition(lhs.count == rhs.count)
        let height = lhs.count / (width * 4)
        return stride(from: 0, to: lhs.count, by: 4).compactMap { offset in
            guard lhs[offset..<(offset + 4)] != rhs[offset..<(offset + 4)] else { return nil }
            let pixel = offset / 4
            // CGContext bitmap storage is bottom-up. Convert scanlines back
            // to the renderer's top-left viewport contract before checking
            // authored frame and ancestor-clip bounds.
            return (pixel % width, height - 1 - pixel / width)
        }
    }

    private func pixelBounds(_ pixels: [(x: Int, y: Int)]) -> String {
        guard let first = pixels.first else { return "empty" }
        let bounds = pixels.dropFirst().reduce(
            (minX: first.x, maxX: first.x, minY: first.y, maxY: first.y)
        ) { partial, pixel in
            (
                minX: min(partial.minX, pixel.x),
                maxX: max(partial.maxX, pixel.x),
                minY: min(partial.minY, pixel.y),
                maxY: max(partial.maxY, pixel.y)
            )
        }
        return "x=\(bounds.minX)...\(bounds.maxX), y=\(bounds.minY)...\(bounds.maxY)"
    }

    private func rgba(at point: (x: Int, y: Int), in bytes: Data, width: Int, height: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        precondition((0..<width).contains(point.x) && (0..<height).contains(point.y))
        // Bitmap storage is bottom-up; all test points use the renderer's
        // canonical top-left viewport coordinate space.
        let offset = ((height - 1 - point.y) * width + point.x) * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
    }
}
