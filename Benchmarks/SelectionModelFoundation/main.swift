import Foundation

struct Measurement: Codable {
    let name: String
    let objectCount: Int
    let unit: String
    let samples: [Double]
    let p95: Double
}

struct Evidence: Codable {
    let schemaVersion: Int
    let requirementIDs: [String]
    let environment: [String: String]
    let methodology: [String]
    let measurements: [Measurement]
    let maximumResidentBytes: UInt64
    let stableDigests: [String]
    let limitations: [String]
}

func percentile95(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
}

func elapsedMilliseconds(_ operation: () throws -> Void) rethrows -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    try operation()
    return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

func systemValue(_ arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/sysctl")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func maximumResidentBytes() -> UInt64 {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return UInt64(max(0, usage.ru_maxrss))
}

func deterministicUUID(_ value: Int) -> UUID {
    UUID(uuidString: "88888888-8888-4888-8888-\(String(format: "%012x", value + 1))")!
}

func fixture(count: Int) throws -> (SelectionSceneSnapshot, CanvasRenderPlan) {
    let documentID = DocumentID(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
    let pageID = PageID(UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
    let identity = CanvasRenderRequestIdentity(
        documentID: documentID, revision: 1,
        sceneID: CanvasViewportSceneID(UUID(uuidString: "33333333-3333-3333-3333-333333333333")!),
        sceneGeneration: 1, viewportGeneration: 1, scale: try CanvasPixelRatio(2)
    )
    let targets = (0..<count).map { index in
        SelectionTargetSnapshot(
            id: NodeID(deterministicUUID(index)), pageID: pageID, parentID: nil, name: "Object \(index + 1)",
            frame: .init(origin: .init(x: Double(index % 100) * 12, y: Double(index / 100) * 12), size: .init(width: 10, height: 10)),
            clipRect: .init(origin: .init(x: 0, y: 0), size: .init(width: 1_440, height: 1_400)),
            paintOrder: index, isVisible: true, isLocked: false, isAvailable: true
        )
    }
    let renderObjects = targets.map {
        CanvasRenderObject(id: $0.id, frame: $0.frame, clipRect: $0.clipRect, paintOrder: $0.paintOrder,
            style: .container, isVisible: true, accessibilityLabel: $0.name)
    }
    let renderScene = CanvasRenderSceneSnapshot(
        identity: identity, surfaceID: CanvasRenderSurfaceID(UUID(uuidString: "55555555-5555-5555-5555-555555555555")!),
        objects: renderObjects
    )
    let viewport = try CanvasViewportState(
        worldOrigin: .init(x: 0, y: 0), viewportSize: .init(width: 1_000, height: 700),
        contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1_440, height: 1_400)), pixelRatio: .init(2)
    )
    let plan = try CanvasRendererCore().prepare(
        scene: renderScene, overlays: .init(identity: identity, overlays: []), viewport: viewport
    )
    return (.init(identity: identity, activePageID: pageID, activeContainerID: nil, targets: targets), plan)
}

var measurements: [Measurement] = []
var digests: [String] = []
for count in [100, 10_000] {
    let (scene, renderPlan) = try fixture(count: count)
    let registry = SelectionCommandRegistry()
    let planner = SelectionOverlayPlanner()
    var state = SelectionState()
    _ = try registry.adopt(scene, boundary: .documentAdoption, state: &state)
    let command = SelectionCommand(.next, expectedIdentity: scene.identity, provenance: .keyboard)
    for _ in 0..<2 {
        _ = try registry.apply(command, to: &state, scene: scene)
        _ = try planner.plan(selection: state, scene: scene, renderPlan: renderPlan)
    }
    var traversal: [Double] = []
    var overlay: [Double] = []
    for _ in 0..<15 {
        traversal.append(try elapsedMilliseconds { _ = try registry.apply(command, to: &state, scene: scene) })
        overlay.append(try elapsedMilliseconds { _ = try planner.plan(selection: state, scene: scene, renderPlan: renderPlan) })
    }
    measurements.append(.init(name: "selection-command", objectCount: count, unit: "milliseconds", samples: traversal, p95: percentile95(traversal)))
    measurements.append(.init(name: "selection-overlay-plan", objectCount: count, unit: "milliseconds", samples: overlay, p95: percentile95(overlay)))
    digests.append(state.orderedIDs.map(\.description).joined(separator: ","))
}

let evidence = Evidence(
    schemaVersion: 1,
    requirementIDs: SelectionCommandRegistry.requirementIDs.sorted(),
    environment: [
        "hardware": systemValue(["-n", "hw.model"]),
        "processor": systemValue(["-n", "machdep.cpu.brand_string"]),
        "os": ProcessInfo.processInfo.operatingSystemVersionString,
        "swift": "Swift 6 optimized (-O)",
    ],
    methodology: [
        "Production SelectionCommandRegistry and SelectionOverlayPlanner compiled with -O.",
        "Two warm-up iterations followed by 15 monotonic-clock samples per operation and fixture size.",
        "Fixtures use non-overlapping, non-empty stable selection targets and the production renderer plan.",
        "P95 uses nearest-rank ordering; resident memory is the process high-water mark after both fixtures.",
    ],
    measurements: measurements,
    maximumResidentBytes: maximumResidentBytes(),
    stableDigests: digests,
    limitations: [
        "These headless measurements do not establish final interactive frame pacing, Instruments allocations, or owner-approved release budgets.",
        "The 10,000-object fixture measures bounded full-snapshot validation; later incremental indexing may be required.",
        "Visual overlay drawing, production text shaping, image decoding, transforms, and export generation are outside SF-AUTHORING-004.",
    ]
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
FileHandle.standardOutput.write(try encoder.encode(evidence))
FileHandle.standardOutput.write(Data("\n".utf8))
