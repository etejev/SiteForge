import AppKit
import CryptoKit
import Foundation

@main
@MainActor
struct AuthoringEngineRunwayMain {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard let outputIndex = arguments.firstIndex(of: "--output"), arguments.indices.contains(outputIndex + 1) else {
            throw RunwayCLIError.usage
        }
        let outputURL = URL(fileURLWithPath: arguments[outputIndex + 1])
        let warmups = 3
        let repetitions = 20
        let layoutRepetitions = 30
        var measurements: [RunwayMeasurement] = []

        let coordinate = try coordinateEvidence()
        let canvasBenchmarks = RunwayCanvasBenchmarks()
        var metalAvailable = false
        for count in [100, 10_000] {
            let objects = RunwayFixtures.canvasObjects(count: count)
            measurements += try canvasBenchmarks.appKitMeasurements(
                objects: objects, warmups: warmups, repetitions: repetitions
            )
            measurements += try canvasBenchmarks.swiftUIMeasurements(
                objects: objects, warmups: warmups, repetitions: repetitions
            )
            measurements += try canvasBenchmarks.coreAnimationMeasurements(
                objects: objects, warmups: warmups, repetitions: repetitions
            )
            let metal = canvasBenchmarks.metalMeasurements(
                objects: objects, warmups: warmups, repetitions: repetitions
            )
            measurements += metal.0
            metalAvailable = metalAvailable || metal.1
            measurements.append(canvasBenchmarks.accessibilityMeasurement(
                objects: objects, warmups: warmups, repetitions: repetitions
            ))
            let hitIndex = RunwayHitIndex(objects: objects)
            var hitSequence = 0
            measurements.append(RunwayBenchmark.measure(
                domain: "canvas", alternative: "UI-independent uniform-grid index", operation: "hit test",
                fixtureCount: count, warmups: warmups, repetitions: 2_000,
                notes: ["Hit-testing remains separate from drawing and editor overlay passes."]
            ) {
                let object = objects[hitSequence % objects.count]
                hitSequence += 1
                _ = hitIndex.hitTest(RunwayPoint(
                    x: object.bounds.origin.x + 1,
                    y: object.bounds.origin.y + 1
                ))
            })
        }

        let layoutEngine = RunwayLayoutEngine()
        var layoutDigestStable = true
        var cancellationObserved = false
        var staleRejected = false
        var largeParityErrors: [String: Double] = [:]
        for count in [100, 10_000] {
            let fixture = RunwayFixtures.largeLayout(nodeCount: count)
            let viewport = RunwaySize(width: 1_200, height: 800)
            let reference = try layoutEngine.layout(root: fixture, viewport: viewport, revision: 7)
            let second = try layoutEngine.layout(root: fixture, viewport: viewport, revision: 7)
            layoutDigestStable = layoutDigestStable && reference.deterministicDigest() == second.deterministicDigest()
            measurements.append(try RunwayBenchmark.measure(
                domain: "layout", alternative: "SiteForge deterministic subset", operation: "complete layout",
                fixtureCount: count, warmups: 5, repetitions: layoutRepetitions,
                digest: reference.deterministicDigest(),
                notes: ["Foundation-only typed model; no AppKit, SwiftUI, WebKit, or canonical-document mutation."]
            ) {
                _ = try layoutEngine.layout(root: fixture, viewport: viewport, revision: 7)
            })
            do {
                _ = try layoutEngine.layout(
                    root: fixture, viewport: viewport, revision: 8,
                    cancellation: { visited in visited >= 64 }
                )
            } catch RunwayError.cancelled {
                cancellationObserved = true
            }
            let versioned = RunwayVersionedResult(revision: 8, value: reference)
            staleRejected = staleRejected || versioned.value(ifCurrent: 9) == nil
        }

        let browser = RunwayBrowserBenchmarks()
        let parityWidths = [320.0, 768.0, 1_440.0]
        let browserParityError = try await browser.parity(root: RunwayFixtures.parityLayout(), widths: parityWidths)
        for count in [100, 10_000] {
            let fixture = RunwayFixtures.largeLayout(nodeCount: count)
            let viewport = RunwaySize(width: 1_200, height: 800)
            measurements.append(try await browser.measurement(
                root: fixture, nodeCount: count,
                viewport: viewport,
                warmups: count == 100 ? 2 : 1,
                repetitions: count == 100 ? 10 : 5
            ))
            largeParityErrors[String(count)] = try await browser.parity(root: fixture, viewport: viewport)
        }

        var invalidInputRejected = false
        var invalid = RunwayFixtures.parityLayout()
        invalid.gap = -1
        do {
            _ = try layoutEngine.layout(
                root: invalid, viewport: RunwaySize(width: 800, height: 360), revision: 1
            )
        } catch RunwayError.invalidConstraints {
            invalidInputRejected = true
        }
        var unsupportedInputRejected = false
        var unsupported = RunwayFixtures.parityLayout()
        unsupported.axis = nil
        do {
            _ = try layoutEngine.layout(
                root: unsupported, viewport: RunwaySize(width: 800, height: 360), revision: 1
            )
        } catch RunwayError.unsupportedLayout {
            unsupportedInputRejected = true
        }

        let resource = try await resourceEvidence(measurements: &measurements)
        let canvasObjects = RunwayFixtures.canvasObjects(count: 100)
        let contentDigest = canvasDigest(canvasObjects)
        let overlay = RunwayOverlay(target: canvasObjects[0].id, bounds: canvasObjects[0].bounds)
        _ = overlay
        let correctness = RunwayCorrectnessEvidence(
            coordinateMaximumRoundTripError: coordinate.roundTrip,
            zoomAnchorMaximumError: coordinate.zoomAnchor,
            panDeltaMaximumError: coordinate.pan,
            overlayContentDigestUnchanged: contentDigest == canvasDigest(canvasObjects),
            nativeMaterialPassThrough: canvasBenchmarks.materialPassThroughCheck(objects: canvasObjects),
            browserParityMaximumPointError: browserParityError,
            browserParityWidths: parityWidths,
            largeFixtureBrowserParityMaximumPointError: largeParityErrors,
            repeatedLayoutDigestStable: layoutDigestStable,
            invalidInputRejected: invalidInputRejected,
            unsupportedInputRejected: unsupportedInputRejected,
            cancellationObserved: cancellationObserved,
            staleResultRejected: staleRejected,
            metalAvailable: metalAvailable
        )
        guard coordinate.roundTrip <= 1e-9, coordinate.zoomAnchor <= 1e-9, coordinate.pan <= 1e-9,
              correctness.overlayContentDigestUnchanged, correctness.nativeMaterialPassThrough,
              browserParityError <= 0.51,
              largeParityErrors.values.allSatisfy({ $0 <= 0.51 }),
              layoutDigestStable, invalidInputRejected, unsupportedInputRejected,
              cancellationObserved, staleRejected else {
            throw RunwayCLIError.correctnessFailure
        }

        let formatter = ISO8601DateFormatter()
        let report = RunwayReport(
            schemaVersion: 1,
            generatedAt: formatter.string(from: Date()),
            sourceBaseRevision: "05dc64b60f21cd6ef6dde06c51e3b6db024db2cd",
            configuration: [
                "canvasWarmups": String(warmups),
                "canvasRepetitions": String(repetitions),
                "layoutWarmups": "5",
                "layoutRepetitions": String(layoutRepetitions),
                "browser100Repetitions": "10",
                "browser10000Repetitions": "5",
                "coordinateTolerancePoints": "1e-9",
                "browserParityTolerancePoints": "0.51",
                "frameIntervalReferenceMilliseconds": "16.67",
            ],
            environment: RunwayBenchmark.environment(),
            correctness: correctness,
            resourceEvidence: resource,
            measurements: measurements,
            limitations: [
                "Offscreen raster timings exclude WindowServer presentation, display refresh synchronization, and interactive Instruments traces.",
                "Process memory is sampled before/after each scenario; peak resident memory is the process-wide high-water mark, not isolated per alternative.",
                "Metal evidence covers buffer and command overhead only; it does not claim a production renderer or shader comparison.",
                "WebKit is an ephemeral geometry oracle and export adapter; it is not editable canonical state.",
                "Accessibility measurements construct AppKit semantic elements but do not measure VoiceOver speech or user navigation.",
                "Resource creation and validation are measured independently and excluded from canvas/layout timings.",
                "Results describe this named machine and toolchain; OD-001 still blocks cross-hardware release budgets.",
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(report)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)
        print("Authoring runway benchmark passed: \(measurements.count) measurements written.")
    }

    private static func coordinateEvidence() throws -> (roundTrip: Double, zoomAnchor: Double, pan: Double) {
        var maximumRoundTrip = 0.0
        var maximumZoomAnchor = 0.0
        var maximumPan = 0.0
        for index in 0..<10_000 {
            let point = RunwayPoint(
                x: Double(index % 997) * 0.125 - 61.5,
                y: Double(index % 991) * -0.0625 + 47.25
            )
            let transform = try RunwayViewportTransform(
                zoom: 0.125 + Double(index % 32) * 0.125,
                pan: RunwayPoint(x: 37.25, y: -18.75), backingScale: index.isMultiple(of: 2) ? 2 : 1
            )
            let roundTrip = transform.deviceToView(transform.viewToDevice(transform.worldToView(point)))
            let recovered = transform.viewToWorld(roundTrip)
            maximumRoundTrip = max(maximumRoundTrip, abs(point.x - recovered.x), abs(point.y - recovered.y))

            let cursor = RunwayPoint(x: 300.25, y: 240.75)
            let anchored = transform.viewToWorld(cursor)
            let zoomed = try transform.zoomed(to: transform.zoom * 1.75, around: cursor)
            let after = zoomed.worldToView(anchored)
            maximumZoomAnchor = max(maximumZoomAnchor, abs(cursor.x - after.x), abs(cursor.y - after.y))

            let delta = RunwayPoint(x: 4.5, y: -3.25)
            let panned = try transform.panned(by: delta)
            let before = transform.worldToView(point)
            let moved = panned.worldToView(point)
            maximumPan = max(maximumPan, abs((moved.x - before.x) - delta.x), abs((moved.y - before.y) - delta.y))
        }
        return (maximumRoundTrip, maximumZoomAnchor, maximumPan)
    }

    private static func resourceEvidence(
        measurements: inout [RunwayMeasurement]
    ) async throws -> RunwayResourceEvidence {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("siteforge-authoring-resource-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixtureRoot.path)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let store = ProjectResourceStore(root: fixtureRoot.appendingPathComponent("Project.siteforge.resources-v1"))
        var descriptors: [ProjectResourceDescriptor] = []
        var nextIndex = 0
        let bytesPerResource = 32 * 1_024
        measurements.append(try await RunwayBenchmark.measureAsync(
            domain: "resource", alternative: "resource-index-v1 content-addressed store",
            operation: "durable resource insertion", fixtureCount: 500,
            warmups: 0, repetitions: 500,
            notes: ["Each sample writes one non-empty 32-KiB resource with integrity and durability policy."]
        ) {
            let index = nextIndex
            nextIndex += 1
            let bytes = representativeAsset(index: index, count: bytesPerResource)
            let id = ResourceID(uuidString: String(format: "70000000-0000-0000-0000-%012d", index + 1))!
            descriptors.append(try await store.put(
                id: id, filename: "asset-\(index).png", mediaType: "image/png", data: bytes
            ))
        })
        let index = ProjectResourceIndex(resources: descriptors.reversed())
        try index.validate()
        measurements.append(try await RunwayBenchmark.measureAsync(
            domain: "resource", alternative: "resource-index-v1 content-addressed store",
            operation: "streamed 500-resource validation", fixtureCount: 500,
            warmups: 1, repetitions: 5,
            notes: ["Validation streams 64-KiB chunks and does not load all resource bytes at once."]
        ) { try await store.validate(index) })
        let probe = index.resources[237]
        var lazyRead = Data()
        measurements.append(try await RunwayBenchmark.measureAsync(
            domain: "resource", alternative: "resource-index-v1 content-addressed store",
            operation: "one-resource lazy read", fixtureCount: 500,
            warmups: 2, repetitions: 20
        ) { lazyRead = try await store.data(for: probe) })
        let memberA = try index.encodedMember().data
        var generator = DeterministicGenerator(seed: 9)
        let shuffled = descriptors.shuffled(using: &generator)
        let memberB = try ProjectResourceIndex(resources: shuffled).encodedMember().data
        let package = try ProjectPackage(document: ProjectCreation.blank()).withResourceIndex(index)
        let packageBytes = try await ProjectPackageStore().encode(package)
        return RunwayResourceEvidence(
            resourceCount: descriptors.count,
            bytesPerResource: bytesPerResource,
            totalResourceBytes: descriptors.count * bytesPerResource,
            deterministicIndex: memberA == memberB,
            encodedIndexBytes: memberA.count,
            encodedControlPackageBytes: packageBytes.count,
            packageParserLimitBytes: ProjectPackageStore.maximumPackageBytes,
            lazyReadMatched: lazyRead == representativeAsset(index: 237, count: bytesPerResource),
            fixtureConstructionExcludedFromCanvasAndLayoutMeasurements: true
        )
    }

    private static func representativeAsset(index: Int, count: Int) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: index &* 31 &+ $0 &* 17) })
    }

    private static func canvasDigest(_ objects: [RunwayCanvasObject]) -> String {
        var hash = SHA256()
        for object in objects {
            hash.update(data: Data("\(object.id):\(object.bounds)".utf8))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private struct DeterministicGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}

private enum RunwayCLIError: Error {
    case usage
    case correctnessFailure
}
