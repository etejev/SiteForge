import AppKit
import XCTest
@testable import SiteForge

@MainActor
final class CanvasTextRenderingTests: XCTestCase {
    // SF-0405-006, SF-0406-001, SF-0406-002, SF-0406-005 — committed text is
    // drawn by the native tile layer after the editor-only draft has gone away.
    func testCommittedPlainTextChangesNativeTilePixelsWithinItsClippedFrame() throws {
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
        let withoutText = rasterizedBytes(object: base, viewport: viewport)
        let withText = rasterizedBytes(
            object: CanvasRenderObject(
                id: base.id, frame: base.frame, clipRect: base.clipRect,
                paintOrder: base.paintOrder, style: base.style, isVisible: base.isVisible,
                accessibilityLabel: base.accessibilityLabel, plainText: "Committed text"
            ),
            viewport: viewport
        )
        let changed = changedPixels(from: withoutText, to: withText, width: 300)
        XCTAssertFalse(changed.isEmpty)
        XCTAssertTrue(
            changed.allSatisfy { (32..<212).contains($0.x) && (16..<66).contains($0.y) },
            "Committed-text pixels escaped the authored frame: \(pixelBounds(changed))"
        )

        let clipped = CanvasRenderObject(
            id: base.id, frame: base.frame,
            clipRect: .init(origin: .init(x: 32, y: 24), size: .init(width: 40, height: 42)),
            paintOrder: base.paintOrder, style: base.style, isVisible: base.isVisible,
            accessibilityLabel: base.accessibilityLabel, plainText: "Committed text"
        )
        let clippedWithoutText = rasterizedBytes(
            object: CanvasRenderObject(
                id: base.id, frame: base.frame,
                clipRect: clipped.clipRect, paintOrder: base.paintOrder,
                style: base.style, isVisible: base.isVisible,
                accessibilityLabel: base.accessibilityLabel
            ),
            viewport: viewport
        )
        let clippedChanged = changedPixels(
            from: clippedWithoutText,
            to: rasterizedBytes(object: clipped, viewport: viewport),
            width: 300
        )
        XCTAssertFalse(clippedChanged.isEmpty)
        XCTAssertTrue(
            clippedChanged.allSatisfy { (32..<72).contains($0.x) && (16..<66).contains($0.y) },
            "Committed-text pixels escaped the authored clip: \(pixelBounds(clippedChanged))"
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
            frameLabelPixels.allSatisfy { (32..<212).contains($0.x) && (16..<66).contains($0.y) },
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
}
