import AppKit
import Metal
import QuartzCore
import SwiftUI

@MainActor
final class RunwayAppKitCanvasView: NSView {
    var objects: [RunwayCanvasObject]

    init(frame: CGRect, objects: [RunwayCanvasObject]) {
        self.objects = objects
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        context.fill(dirtyRect)
        for object in objects where dirtyRect.intersects(object.bounds.cgRect) {
            context.setFillColor(object.cgColor)
            context.fill(object.bounds.cgRect)
        }
    }
}

struct RunwaySwiftUICanvas: View {
    let objects: [RunwayCanvasObject]
    let size: CGSize

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(nsColor: .windowBackgroundColor)))
            for object in objects {
                context.fill(Path(object.bounds.cgRect), with: .color(Color(nsColor: object.nsColor)))
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

@MainActor
final class RunwayCanvasBenchmarks {
    let pixelSize = CGSize(width: 1_200, height: 800)

    func appKitMeasurements(objects: [RunwayCanvasObject], warmups: Int, repetitions: Int) throws -> [RunwayMeasurement] {
        let view = RunwayAppKitCanvasView(frame: CGRect(origin: .zero, size: pixelSize), objects: objects)
        let full = try RunwayBenchmark.measure(
            domain: "canvas", alternative: "AppKit immediate drawing", operation: "full bitmap raster",
            fixtureCount: objects.count, warmups: warmups, repetitions: repetitions,
            notes: ["One flipped NSView; dirty-rect culling; no window compositor time included."]
        ) { try self.render(view: view, dirtyRect: view.bounds) }
        let changedIndex = max(0, objects.count / 2)
        let dirty = objects.isEmpty ? view.bounds : objects[changedIndex].bounds.cgRect.insetBy(dx: -1, dy: -1)
        var toggle = false
        let incremental = try RunwayBenchmark.measure(
            domain: "canvas", alternative: "AppKit immediate drawing", operation: "single-object dirty raster",
            fixtureCount: objects.count, warmups: warmups, repetitions: repetitions,
            notes: ["Measures one bounded invalidation region, including scan-based dirty culling."]
        ) {
            if !view.objects.isEmpty {
                toggle.toggle()
                view.objects[changedIndex].bounds.origin.x += toggle ? 0.25 : -0.25
            }
            try self.render(view: view, dirtyRect: dirty)
        }
        return [full, incremental]
    }

    func swiftUIMeasurements(objects: [RunwayCanvasObject], warmups: Int, repetitions: Int) throws -> [RunwayMeasurement] {
        var current = objects
        let full = try RunwayBenchmark.measure(
            domain: "canvas", alternative: "SwiftUI Canvas", operation: "full ImageRenderer raster",
            fixtureCount: objects.count, warmups: warmups, repetitions: repetitions,
            notes: ["Offscreen ImageRenderer includes SwiftUI Canvas evaluation and rasterization, not window presentation."]
        ) { try self.renderSwiftUI(objects: current) }
        let changedIndex = max(0, objects.count / 2)
        var toggle = false
        let incremental = try RunwayBenchmark.measure(
            domain: "canvas", alternative: "SwiftUI Canvas", operation: "single-model-change full raster",
            fixtureCount: objects.count, warmups: warmups, repetitions: repetitions,
            notes: ["SwiftUI Canvas has one render closure; this prototype rerasterizes the surface after one model change."]
        ) {
            if !current.isEmpty {
                toggle.toggle()
                current[changedIndex].bounds.origin.x += toggle ? 0.25 : -0.25
            }
            try self.renderSwiftUI(objects: current)
        }
        return [full, incremental]
    }

    func coreAnimationMeasurements(objects: [RunwayCanvasObject], warmups: Int, repetitions: Int) throws -> [RunwayMeasurement] {
        let root = makeLayerTree(objects: objects)
        let full = try RunwayBenchmark.measure(
            domain: "canvas", alternative: "Core Animation layer per object", operation: "full layer-tree raster",
            fixtureCount: objects.count, warmups: warmups, repetitions: repetitions,
            notes: ["Measures CALayer.render(in:) for a retained layer per object; compositor presentation is excluded."]
        ) { try self.render(layer: root) }
        let changedIndex = max(0, objects.count / 2)
        var toggle = false
        let incremental = RunwayBenchmark.measure(
            domain: "canvas", alternative: "Core Animation layer per object", operation: "single-layer transaction",
            fixtureCount: objects.count, warmups: warmups, repetitions: repetitions,
            notes: ["Measures CPU-side retained-layer mutation only; GPU composition latency is not claimed."]
        ) {
            guard let layers = root.sublayers, !layers.isEmpty else { return }
            toggle.toggle()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layers[changedIndex].position.x += toggle ? 0.25 : -0.25
            CATransaction.commit()
        }
        return [full, incremental]
    }

    func metalMeasurements(objects: [RunwayCanvasObject], warmups: Int, repetitions: Int) -> ([RunwayMeasurement], Bool) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return ([], false) }
        var packed = objects.map {
            SIMD4<Float>(Float($0.bounds.origin.x), Float($0.bounds.origin.y), Float($0.bounds.size.width), Float($0.bounds.size.height))
        }
        let length = max(1, packed.count * MemoryLayout<SIMD4<Float>>.stride)
        guard let buffer = packed.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: length) }) else {
            return ([], false)
        }
        let measurement = RunwayBenchmark.measure(
            domain: "canvas", alternative: "Metal data/command runway", operation: "single-buffer-update command round trip",
            fixtureCount: objects.count, warmups: warmups, repetitions: repetitions,
            notes: [
                "Measures CPU buffer mutation and an empty committed command buffer.",
                "No shader, texture raster, presentation, hit testing, overlays, or accessibility integration is claimed.",
            ]
        ) {
            if !packed.isEmpty {
                packed[packed.count / 2].x += 0.25
                buffer.contents().copyMemory(from: packed, byteCount: packed.count * MemoryLayout<SIMD4<Float>>.stride)
            }
            let command = queue.makeCommandBuffer()!
            command.commit()
            command.waitUntilCompleted()
        }
        return ([measurement], true)
    }

    func accessibilityMeasurement(objects: [RunwayCanvasObject], warmups: Int, repetitions: Int) -> RunwayMeasurement {
        let container = NSView(frame: CGRect(origin: .zero, size: pixelSize))
        return RunwayBenchmark.measure(
            domain: "accessibility", alternative: "AppKit virtual accessibility elements",
            operation: "construct accessibility snapshot", fixtureCount: objects.count,
            warmups: warmups, repetitions: repetitions,
            notes: ["Constructs roles, labels, identifiers, and frames; VoiceOver traversal/speech latency is not measured."]
        ) {
            _ = objects.map { object -> NSAccessibilityElement in
                let element = NSAccessibilityElement()
                element.setAccessibilityParent(container)
                element.setAccessibilityRole(.group)
                element.setAccessibilityLabel("Canvas object")
                element.setAccessibilityIdentifier("runway.\(object.id.rawValue)")
                element.setAccessibilityFrame(object.bounds.cgRect)
                return element
            }
        }
    }

    func materialPassThroughCheck(objects: [RunwayCanvasObject]) -> Bool {
        let container = NSView(frame: CGRect(origin: .zero, size: pixelSize))
        let canvas = RunwayAppKitCanvasView(frame: container.bounds, objects: objects)
        let material = RunwayPassThroughMaterial(frame: container.bounds)
        material.material = .sidebar
        material.blendingMode = .behindWindow
        material.state = .active
        container.addSubview(canvas)
        container.addSubview(material)
        let point = NSPoint(x: 20, y: 20)
        return material.hitTest(point) == nil && container.hitTest(point) === canvas
    }

    private func render(view: RunwayAppKitCanvasView, dirtyRect: CGRect) throws {
        guard let context = makeBitmapContext() else { throw RunwayError.oracleFailure }
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        view.displayIgnoringOpacity(dirtyRect, in: graphics)
    }

    private func renderSwiftUI(objects: [RunwayCanvasObject]) throws {
        let renderer = ImageRenderer(content: RunwaySwiftUICanvas(objects: objects, size: pixelSize))
        renderer.proposedSize = ProposedViewSize(width: pixelSize.width, height: pixelSize.height)
        renderer.scale = 1
        guard renderer.cgImage != nil else { throw RunwayError.oracleFailure }
    }

    private func makeLayerTree(objects: [RunwayCanvasObject]) -> CALayer {
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: pixelSize)
        root.isGeometryFlipped = true
        root.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.sublayers = objects.map { object in
            let layer = CALayer()
            layer.frame = object.bounds.cgRect
            layer.backgroundColor = object.cgColor
            layer.actions = ["position": NSNull(), "bounds": NSNull(), "backgroundColor": NSNull()]
            return layer
        }
        return root
    }

    private func render(layer: CALayer) throws {
        guard let context = makeBitmapContext() else { throw RunwayError.oracleFailure }
        layer.render(in: context)
    }

    private func makeBitmapContext() -> CGContext? {
        CGContext(
            data: nil,
            width: Int(pixelSize.width), height: Int(pixelSize.height),
            bitsPerComponent: 8, bytesPerRow: Int(pixelSize.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}

@MainActor
private final class RunwayPassThroughMaterial: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private extension RunwayRect {
    var cgRect: CGRect {
        CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }
}

private extension RunwayCanvasObject {
    var nsColor: NSColor {
        NSColor(
            calibratedRed: CGFloat((colorSeed >> 16) & 0xff) / 255,
            green: CGFloat((colorSeed >> 8) & 0xff) / 255,
            blue: CGFloat(colorSeed & 0xff) / 255,
            alpha: 1
        )
    }
    var cgColor: CGColor { nsColor.cgColor }
}
