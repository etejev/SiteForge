import CoreVideo
import Foundation

private struct RendererCorrectness: Codable {
    let deterministicDigestsStable: Bool
    let overlayExcludedFromPreview: Bool
    let cancellationObserved: Bool
    let staleResultRejected: Bool
    let compositorOnlyHasNoDirtyRegions: Bool
    let maximumTileCount: Int
    let maximumAccessibilityCount: Int
    let displayLinkFrames: Int
    let displayLinkStalls: Int
}

private struct RendererReport: Codable {
    let schemaVersion: Int
    let generatedAt: String
    let environment: RunwayEnvironment
    let configuration: [String: String]
    let correctness: RendererCorrectness
    let measurements: [RunwayMeasurement]
    let limitations: [String]
}

private final class DisplayLinkProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var times: [UInt64] = []

    func record(_ time: UInt64) {
        lock.lock(); times.append(time); lock.unlock()
    }

    func result(frequency: Double) -> (Int, Int) {
        lock.lock(); defer { lock.unlock() }
        let secondsPerTick = frequency > 0 ? 1 / frequency : 0
        let expected = 1.0 / 60.0
        let stalls = zip(times, times.dropFirst()).filter {
            Double($0.1 - $0.0) * secondsPerTick > expected * 2
        }.count
        return (times.count, stalls)
    }
}

private func displayLinkCallback(
    _: CVDisplayLink,
    _: UnsafePointer<CVTimeStamp>,
    output: UnsafePointer<CVTimeStamp>,
    _: CVOptionFlags,
    _: UnsafeMutablePointer<CVOptionFlags>,
    context: UnsafeMutableRawPointer?
) -> CVReturn {
    guard let context else { return kCVReturnError }
    Unmanaged<DisplayLinkProbe>.fromOpaque(context).takeUnretainedValue().record(output.pointee.hostTime)
    return kCVReturnSuccess
}

@main
struct CanvasRendererFoundationMain {
    static func main() throws {
        guard let index = CommandLine.arguments.firstIndex(of: "--output"),
              CommandLine.arguments.indices.contains(index + 1) else { throw CocoaError(.fileNoSuchFile) }
        let output = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        let core = CanvasRendererCore()
        var measurements: [RunwayMeasurement] = []
        var stable = true
        var maxTiles = 0
        var maxAccessibility = 0
        var cancellation = false
        var stale = false
        var overlayExcluded = false
        var compositorClean = false

        for count in [100, 10_000] {
            let fixture = try makeFixture(count: count)
            let reference = try core.prepare(scene: fixture.scene, overlays: fixture.overlays, viewport: fixture.viewport)
            let repeated = try core.prepare(scene: fixture.scene, overlays: fixture.overlays, viewport: fixture.viewport)
            stable = stable && reference.deterministicDigest == repeated.deterministicDigest
            maxTiles = max(maxTiles, reference.tiles.count)
            maxAccessibility = max(maxAccessibility, reference.accessibilityElements.count)
            measurements.append(try RunwayBenchmark.measure(
                domain: "production-renderer", alternative: "Foundation scene preparation", operation: "full initial plan",
                fixtureCount: count, warmups: 5, repetitions: 30, digest: reference.deterministicDigest,
                notes: ["Includes validation, paint ordering, bounded tile membership, accessibility virtualization, dirty policy, and digest; excludes fixture construction and AppKit layer adoption."]
            ) { _ = try core.prepare(scene: fixture.scene, overlays: fixture.overlays, viewport: fixture.viewport) })

            var changed = fixture.scene.objects
            let target = changed[count / 2]
            changed[count / 2] = CanvasRenderObject(
                id: target.id,
                frame: WorldRect(origin: WorldPoint(x: target.frame.origin.x + 4, y: target.frame.origin.y + 3), size: target.frame.size),
                clipRect: target.clipRect, paintOrder: target.paintOrder, style: target.style,
                isVisible: target.isVisible, accessibilityLabel: target.accessibilityLabel
            )
            let changedScene = CanvasRenderSceneSnapshot(identity: fixture.scene.identity, surfaceID: fixture.scene.surfaceID, objects: changed)
            measurements.append(try RunwayBenchmark.measure(
                domain: "production-renderer", alternative: "Foundation scene preparation", operation: "one-object dirty plan",
                fixtureCount: count, warmups: 5, repetitions: 30,
                notes: ["One changed object produces only old/new dirty regions; layer adoption redraws affected bounded tiles."]
            ) { _ = try core.prepare(scene: changedScene, overlays: fixture.overlays, viewport: fixture.viewport, previous: fixture.scene) })

            let compositor = try core.prepare(scene: fixture.scene, overlays: fixture.overlays, viewport: fixture.viewport, previous: fixture.scene)
            compositorClean = compositorClean || (compositor.invalidation == .compositorOnly && compositor.dirtyWorldRegions.isEmpty)
            var sequence = 0
            measurements.append(RunwayBenchmark.measure(
                domain: "production-renderer", alternative: "Reverse paint-order hit testing", operation: "hit test",
                fixtureCount: count, warmups: 5, repetitions: 2_000,
                notes: ["Hit testing is UI-independent and excludes editor overlays."]
            ) {
                let object = reference.authoredObjects[sequence % reference.authoredObjects.count]
                sequence += 1
                _ = core.hitTest(WorldPoint(x: object.frame.origin.x + 1, y: object.frame.origin.y + 1), in: reference)
            })
            do {
                _ = try core.prepare(
                    scene: fixture.scene, overlays: fixture.overlays, viewport: fixture.viewport,
                    cancellation: CanvasRenderCancellation { $0 >= 64 }
                )
            } catch CanvasRendererError.cancelled { cancellation = true }
            do {
                try CanvasRenderAdoptionGate().validate(reference, expected: staleIdentity(fixture.scene.identity))
            } catch CanvasRendererError.staleResult { stale = true }
            let overlay = CanvasEditorOverlay(
                id: CanvasOverlayID(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!),
                objectID: fixture.scene.objects[0].id, frame: fixture.scene.objects[0].frame, kind: "selection"
            )
            _ = try core.prepare(
                scene: fixture.scene,
                overlays: CanvasEditorOverlaySnapshot(identity: fixture.scene.identity, overlays: [overlay]),
                viewport: fixture.viewport
            )
            overlayExcluded = overlayExcluded || !String(describing: core.previewSnapshot(from: fixture.scene)).contains("selection")
        }

        let display = displayLinkEvidence()
        let report = RendererReport(
            schemaVersion: 1,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            environment: RunwayBenchmark.environment(),
            configuration: [
                "optimization": "swiftc -O -swift-version 6",
                "warmups": "5", "repetitions": "30", "hitTestRepetitions": "2000",
                "frameIntervalReferenceMilliseconds": "16.67", "tileDevicePixels": "512",
                "cacheLimitBytes": String(CanvasRendererPolicy.maximumCacheBytes),
            ],
            correctness: RendererCorrectness(
                deterministicDigestsStable: stable, overlayExcludedFromPreview: overlayExcluded,
                cancellationObserved: cancellation, staleResultRejected: stale,
                compositorOnlyHasNoDirtyRegions: compositorClean, maximumTileCount: maxTiles,
                maximumAccessibilityCount: maxAccessibility,
                displayLinkFrames: display.0, displayLinkStalls: display.1
            ),
            measurements: measurements,
            limitations: [
                "Measurements describe one named host and do not establish OD-001 release budgets.",
                "Foundation preparation timings exclude fixture construction, AppKit layer adoption, WindowServer presentation, and GPU compositor cost.",
                "The display-link probe records callback cadence during an idle 250 ms observation; it is not an interactive trace or Instruments capture.",
                "Process memory is sampled before and after sequential scenarios; peak resident memory is process-wide.",
                "The production UI test exercises the real AppKit/Core Animation surface, but automated tests do not claim VoiceOver speech.",
                "No canonical editing, selection engine, export generator, text shaping, image decoding, or Metal backend is included.",
            ]
        )
        guard stable, overlayExcluded, cancellation, stale, compositorClean, display.0 > 0 else {
            throw CocoaError(.propertyListWriteInvalid)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(report).write(to: output, options: .atomic)
        print("Canvas renderer evidence passed: \(measurements.count) measurements, \(display.0) display-link callbacks, \(display.1) stalls.")
    }

    private static func displayLinkEvidence() -> (Int, Int) {
        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess, let link else { return (0, 0) }
        let probe = DisplayLinkProbe()
        let context = Unmanaged.passUnretained(probe).toOpaque()
        CVDisplayLinkSetOutputCallback(link, displayLinkCallback, context)
        CVDisplayLinkStart(link)
        Thread.sleep(forTimeInterval: 0.25)
        CVDisplayLinkStop(link)
        return probe.result(frequency: CVGetHostClockFrequency())
    }

    private static func staleIdentity(_ identity: CanvasRenderRequestIdentity) -> CanvasRenderRequestIdentity {
        CanvasRenderRequestIdentity(
            documentID: identity.documentID, revision: identity.revision + 1, sceneID: identity.sceneID,
            sceneGeneration: identity.sceneGeneration, viewportGeneration: identity.viewportGeneration, scale: identity.scale
        )
    }

    private static func makeFixture(count: Int) throws -> (scene: CanvasRenderSceneSnapshot, overlays: CanvasEditorOverlaySnapshot, viewport: CanvasViewportState) {
        let identity = CanvasRenderRequestIdentity(
            documentID: DocumentID(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!), revision: 7,
            sceneID: CanvasViewportSceneID(UUID(uuidString: "22222222-2222-2222-2222-222222222222")!),
            sceneGeneration: 9, viewportGeneration: 11, scale: try CanvasPixelRatio(2)
        )
        let objects = (0..<count).map { index in
            CanvasRenderObject(
                id: NodeID(UUID(uuidString: "44444444-4444-4444-8444-\(String(format: "%012x", index + 1))")!),
                frame: WorldRect(origin: WorldPoint(x: Double((index % 100) * 12), y: Double((index / 100) * 12)), size: WorldSize(width: 10, height: 10)),
                clipRect: WorldRect(origin: WorldPoint(x: 0, y: 0), size: WorldSize(width: 1_440, height: 1_400)),
                paintOrder: index, style: index.isMultiple(of: 2) ? .container : .page,
                isVisible: true, accessibilityLabel: "Object \(index + 1)"
            )
        }
        let viewport = try CanvasViewportState(
            worldOrigin: WorldPoint(x: 0, y: 0), viewportSize: ViewportSize(width: 1_000, height: 700),
            contentBounds: WorldRect(origin: WorldPoint(x: 0, y: 0), size: WorldSize(width: 1_440, height: 1_400)),
            pixelRatio: CanvasPixelRatio(2)
        )
        let scene = CanvasRenderSceneSnapshot(
            identity: identity, surfaceID: CanvasRenderSurfaceID(UUID(uuidString: "33333333-3333-3333-3333-333333333333")!), objects: objects
        )
        return (scene, CanvasEditorOverlaySnapshot(identity: identity, overlays: []), viewport)
    }
}
