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
            changed.allSatisfy { (32..<212).contains($0.x) && (24..<66).contains($0.y) },
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
            clippedChanged.allSatisfy { (32..<72).contains($0.x) && (24..<66).contains($0.y) },
            "Committed-text pixels escaped the authored clip: \(pixelBounds(clippedChanged))"
        )
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
