import CryptoKit
import Foundation

enum CanvasRenderSurfaceDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "render-surface"
}
typealias CanvasRenderSurfaceID = StableIdentifier<CanvasRenderSurfaceDomain>

enum CanvasOverlayDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "editor-overlay"
}
typealias CanvasOverlayID = StableIdentifier<CanvasOverlayDomain>

enum CanvasAccessibilityDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "render-accessibility"
}
typealias CanvasAccessibilityID = StableIdentifier<CanvasAccessibilityDomain>

struct CanvasRenderRequestIdentity: Codable, Hashable, Sendable {
    let documentID: DocumentID
    let revision: UInt64
    let sceneID: CanvasViewportSceneID
    let sceneGeneration: UInt64
    let viewportGeneration: UInt64
    let scale: CanvasPixelRatio
}

enum CanvasPaintStyle: String, Codable, Hashable, Sendable {
    case canvas, page, container, frameSurface, sectionSurface, stackSurface, gridSurface, imagePlaceholder, textPlaceholder
}

struct CanvasRenderObject: Codable, Hashable, Sendable {
    let id: NodeID
    let frame: WorldRect
    let clipRect: WorldRect?
    let paintOrder: Int
    let style: CanvasPaintStyle
    let isVisible: Bool
    let accessibilityLabel: String
    let plainText: String?
    /// A canonical node name is safe to render as authored chrome. It is
    /// deliberately distinct from editor-only selection labels and handles.
    let displayName: String?
    /// Authored color is distinct from `CanvasPaintStyle` (the bounded
    /// renderer's semantic fallback) and from editor-only overlays.
    let fillRGBA: [Double]?
    let opacity: Double

    init(
        id: NodeID,
        frame: WorldRect,
        clipRect: WorldRect?,
        paintOrder: Int,
        style: CanvasPaintStyle,
        isVisible: Bool,
        accessibilityLabel: String,
        plainText: String? = nil,
        displayName: String? = nil,
        fillRGBA: [Double]? = nil,
        opacity: Double = 1
    ) {
        self.id = id
        self.frame = frame
        self.clipRect = clipRect
        self.paintOrder = paintOrder
        self.style = style
        self.isVisible = isVisible
        self.accessibilityLabel = accessibilityLabel
        self.plainText = plainText
        self.displayName = displayName
        self.fillRGBA = fillRGBA
        self.opacity = opacity
    }
}

struct CanvasEditorOverlay: Codable, Hashable, Sendable {
    let id: CanvasOverlayID
    let objectID: NodeID
    let frame: WorldRect
    let kind: String
    /// Selection context is editor-only and intentionally excluded from the
    /// authored render scene, package, history, preview, and export snapshots.
    let label: String?

    init(
        id: CanvasOverlayID,
        objectID: NodeID,
        frame: WorldRect,
        kind: String,
        label: String? = nil
    ) {
        self.id = id
        self.objectID = objectID
        self.frame = frame
        self.kind = kind
        self.label = label
    }
}

struct CanvasRenderSceneSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let identity: CanvasRenderRequestIdentity
    let surfaceID: CanvasRenderSurfaceID
    let objects: [CanvasRenderObject]

    init(
        schemaVersion: Int = currentSchemaVersion,
        identity: CanvasRenderRequestIdentity,
        surfaceID: CanvasRenderSurfaceID,
        objects: [CanvasRenderObject]
    ) {
        self.schemaVersion = schemaVersion
        self.identity = identity
        self.surfaceID = surfaceID
        self.objects = objects
    }
}

struct CanvasEditorOverlaySnapshot: Equatable, Sendable {
    let identity: CanvasRenderRequestIdentity
    let overlays: [CanvasEditorOverlay]
}

struct CanvasPreviewSceneSnapshot: Equatable, Sendable {
    let documentID: DocumentID
    let revision: UInt64
    let objects: [CanvasRenderObject]
    let deterministicDigest: String
}

struct CanvasRenderTileID: Codable, Hashable, Comparable, Sendable {
    let column: Int
    let row: Int
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row ? lhs.column < rhs.column : lhs.row < rhs.row
    }
}

struct CanvasRenderTile: Equatable, Sendable {
    let id: CanvasRenderTileID
    let deviceFrame: DeviceRect
    let objectIDs: [NodeID]
    let estimatedBytes: Int
}

struct CanvasAccessibilityElementSnapshot: Equatable, Sendable {
    let id: CanvasAccessibilityID
    let objectID: NodeID
    let label: String
    let frame: ViewportRect
    let paintOrder: Int
}

enum CanvasAccessibilityFocusPolicy {
    static func repairedFocus(
        previousObjectID: NodeID?,
        elements: [CanvasAccessibilityElementSnapshot]
    ) -> NodeID? {
        guard !elements.isEmpty else { return nil }
        if let previousObjectID, elements.contains(where: { $0.objectID == previousObjectID }) {
            return previousObjectID
        }
        return elements.first?.objectID
    }
}

enum CanvasInvalidationKind: String, Codable, Sendable {
    case initial, dirtyRegions, compositorOnly, fullRaster
}

struct CanvasRenderPlan: Equatable, Sendable {
    let identity: CanvasRenderRequestIdentity
    let surfaceID: CanvasRenderSurfaceID
    /// The immutable viewport snapshot used to allocate this plan's tiles.
    /// Native composition must never substitute a newer live viewport while
    /// adopting the plan; that would separate painted bounds from overlays.
    let viewport: CanvasViewportState
    let authoredObjects: [CanvasRenderObject]
    let tiles: [CanvasRenderTile]
    let accessibilityElements: [CanvasAccessibilityElementSnapshot]
    let dirtyWorldRegions: [WorldRect]
    let invalidation: CanvasInvalidationKind
    let deterministicDigest: String
}

enum CanvasRendererError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedSchema(Int)
    case emptyScene
    case duplicateObject(NodeID)
    case duplicatePaintOrder(Int)
    case invalidObject(NodeID)
    case objectLimitExceeded(Int)
    case tileLimitExceeded(Int)
    case rasterLimitExceeded
    case cacheLimitExceeded
    case cancelled
    case staleResult

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema: "This canvas scene version is not supported. Keep the last valid scene and update SiteForge."
        case .emptyScene: "The canvas scene has no renderable root. Keep the last valid scene and inspect the project."
        case .duplicateObject, .duplicatePaintOrder, .invalidObject:
            "The canvas scene is internally inconsistent. The last valid scene remains displayed."
        case .objectLimitExceeded, .tileLimitExceeded, .rasterLimitExceeded, .cacheLimitExceeded:
            "The canvas exceeds a safe rendering limit. Reduce visible content or zoom out."
        case .cancelled: "Canvas rendering was cancelled. The last valid scene remains displayed."
        case .staleResult: "A newer canvas scene superseded this render."
        }
    }
}

enum CanvasRendererPolicy {
    static let maximumObjects = 20_000
    static let tileDevicePixels = 512
    static let maximumTiles = 512
    static let maximumRasterDimension = 32_768.0
    static let maximumCacheBytes = 96 * 1_024 * 1_024
    static let maximumRetainedGenerations = 2
    static let maximumAccessibilityElements = 256
    static let cancellationStride = 64
}

struct CanvasRenderCancellation: Sendable {
    let isCancelled: @Sendable (Int) -> Bool
    static let never = CanvasRenderCancellation(isCancelled: { _ in false })
}

struct CanvasRendererCore: Sendable {
    static let requirementIDs: Set<String> = [
        "SF-0407-001", "SF-0407-002", "SF-0407-003", "SF-0407-004",
        "SF-0407-005", "SF-0407-006", "SF-0407-007", "SF-0407-008",
    ]

    func prepare(
        scene: CanvasRenderSceneSnapshot,
        overlays: CanvasEditorOverlaySnapshot,
        viewport: CanvasViewportState,
        previous: CanvasRenderSceneSnapshot? = nil,
        cancellation: CanvasRenderCancellation = .never
    ) throws -> CanvasRenderPlan {
        try validate(scene, overlays: overlays, cancellation: cancellation)
        let transform = viewport.transform
        let visible = viewport.visibleWorldRect
        let painted = scene.objects.sorted {
            $0.paintOrder == $1.paintOrder ? $0.id.description < $1.id.description : $0.paintOrder < $1.paintOrder
        }
        let invalidation = invalidation(previous: previous, next: scene)
        let dirty = dirtyRegions(previous: previous, next: scene, invalidation: invalidation)
        let tiles = try buildTiles(objects: painted, viewport: viewport, cancellation: cancellation)
        var accessibility: [CanvasAccessibilityElementSnapshot] = []
        accessibility.reserveCapacity(min(CanvasRendererPolicy.maximumAccessibilityElements, painted.count))
        for object in painted where accessibility.count < CanvasRendererPolicy.maximumAccessibilityElements {
            guard object.isVisible, intersects(object.frame, visible), isInsideClip(object) else { continue }
            let origin = try transform.worldToViewport(object.frame.origin)
            accessibility.append(CanvasAccessibilityElementSnapshot(
                id: accessibilityID(for: object.id),
                objectID: object.id,
                label: object.accessibilityLabel,
                frame: ViewportRect(
                    origin: origin,
                    size: ViewportSize(
                        width: object.frame.size.width * viewport.zoom.value,
                        height: object.frame.size.height * viewport.zoom.value
                    )
                ),
                paintOrder: object.paintOrder
            ))
        }
        return CanvasRenderPlan(
            identity: scene.identity,
            surfaceID: scene.surfaceID,
            viewport: viewport,
            authoredObjects: painted,
            tiles: tiles,
            accessibilityElements: accessibility,
            dirtyWorldRegions: dirty,
            invalidation: invalidation,
            deterministicDigest: digest(scene.objects)
        )
    }

    func hitTest(_ point: WorldPoint, in plan: CanvasRenderPlan) -> NodeID? {
        hitTest(point, in: plan, eligibleIDs: nil)
    }

    func hitTest(_ point: WorldPoint, in plan: CanvasRenderPlan, eligibleIDs: Set<NodeID>?) -> NodeID? {
        plan.authoredObjects.reversed().first { object in
            (eligibleIDs?.contains(object.id) ?? true)
                && object.isVisible
                && contains(object.frame, point)
                && isInsideClip(object, point: point)
        }?.id
    }

    func previewSnapshot(from scene: CanvasRenderSceneSnapshot) -> CanvasPreviewSceneSnapshot {
        CanvasPreviewSceneSnapshot(
            documentID: scene.identity.documentID,
            revision: scene.identity.revision,
            objects: scene.objects,
            deterministicDigest: digest(scene.objects)
        )
    }

    private func validate(
        _ scene: CanvasRenderSceneSnapshot,
        overlays: CanvasEditorOverlaySnapshot,
        cancellation: CanvasRenderCancellation
    ) throws {
        guard scene.schemaVersion == CanvasRenderSceneSnapshot.currentSchemaVersion else {
            throw CanvasRendererError.unsupportedSchema(scene.schemaVersion)
        }
        // An empty scene is a valid, explicit blank-project state. Keeping it
        // renderable means the canvas can adopt a real empty plan rather than
        // retaining a stale scene or fabricating a root-node rectangle.
        guard scene.objects.count <= CanvasRendererPolicy.maximumObjects else {
            throw CanvasRendererError.objectLimitExceeded(scene.objects.count)
        }
        guard overlays.identity == scene.identity else { throw CanvasRendererError.staleResult }
        var ids = Set<NodeID>()
        var orders = Set<Int>()
        for (index, object) in scene.objects.enumerated() {
            if index.isMultiple(of: CanvasRendererPolicy.cancellationStride), cancellation.isCancelled(index) {
                throw CanvasRendererError.cancelled
            }
            guard ids.insert(object.id).inserted else { throw CanvasRendererError.duplicateObject(object.id) }
            guard orders.insert(object.paintOrder).inserted else {
                throw CanvasRendererError.duplicatePaintOrder(object.paintOrder)
            }
            guard object.frame.isValid, object.frame.size.width <= CanvasRendererPolicy.maximumRasterDimension,
                  object.frame.size.height <= CanvasRendererPolicy.maximumRasterDimension,
                  object.clipRect?.isValid != false, !object.accessibilityLabel.isEmpty else {
                throw CanvasRendererError.invalidObject(object.id)
            }
        }
        guard !cancellation.isCancelled(scene.objects.count) else { throw CanvasRendererError.cancelled }
    }

    private func buildTiles(
        objects: [CanvasRenderObject],
        viewport: CanvasViewportState,
        cancellation: CanvasRenderCancellation
    ) throws -> [CanvasRenderTile] {
        let scale = viewport.pixelRatio.value
        let width = viewport.viewportSize.width * scale
        let height = viewport.viewportSize.height * scale
        guard width <= CanvasRendererPolicy.maximumRasterDimension,
              height <= CanvasRendererPolicy.maximumRasterDimension else { throw CanvasRendererError.rasterLimitExceeded }
        let columns = max(1, Int(ceil(width / Double(CanvasRendererPolicy.tileDevicePixels))))
        let rows = max(1, Int(ceil(height / Double(CanvasRendererPolicy.tileDevicePixels))))
        guard columns * rows <= CanvasRendererPolicy.maximumTiles else {
            throw CanvasRendererError.tileLimitExceeded(columns * rows)
        }
        var tiles: [CanvasRenderTile] = []
        tiles.reserveCapacity(columns * rows)
        let transform = viewport.transform
        for row in 0..<rows {
            for column in 0..<columns {
                let x = Double(column * CanvasRendererPolicy.tileDevicePixels)
                let y = Double(row * CanvasRendererPolicy.tileDevicePixels)
                let tileWidth = min(Double(CanvasRendererPolicy.tileDevicePixels), width - x)
                let tileHeight = min(Double(CanvasRendererPolicy.tileDevicePixels), height - y)
                let device = DeviceRect(origin: DevicePoint(x: x, y: y), size: DeviceSize(width: tileWidth, height: tileHeight))
                let viewportOrigin = try transform.deviceToViewport(device.origin)
                let worldOrigin = try transform.viewportToWorld(viewportOrigin)
                let worldFrame = WorldRect(
                    origin: worldOrigin,
                    size: WorldSize(
                        width: tileWidth / scale / viewport.zoom.value,
                        height: tileHeight / scale / viewport.zoom.value
                    )
                )
                let objectIDs = objects.filter { $0.isVisible && intersects($0.frame, worldFrame) && isInsideClip($0) }.map(\.id)
                let bytes = Int(tileWidth * tileHeight * 4)
                tiles.append(CanvasRenderTile(
                    id: CanvasRenderTileID(column: column, row: row),
                    deviceFrame: device,
                    objectIDs: objectIDs,
                    estimatedBytes: bytes
                ))
            }
        }
        let total = tiles.reduce(0) { $0 + $1.estimatedBytes }
        guard total <= CanvasRendererPolicy.maximumCacheBytes else { throw CanvasRendererError.cacheLimitExceeded }
        return tiles
    }

    private func invalidation(previous: CanvasRenderSceneSnapshot?, next: CanvasRenderSceneSnapshot) -> CanvasInvalidationKind {
        guard let previous else { return .initial }
        guard previous.identity.documentID == next.identity.documentID,
              previous.identity.sceneID == next.identity.sceneID,
              previous.identity.scale == next.identity.scale else { return .fullRaster }
        return previous.objects == next.objects ? .compositorOnly : .dirtyRegions
    }

    private func dirtyRegions(
        previous: CanvasRenderSceneSnapshot?,
        next: CanvasRenderSceneSnapshot,
        invalidation: CanvasInvalidationKind
    ) -> [WorldRect] {
        guard invalidation == .dirtyRegions, let previous else {
            return invalidation == .compositorOnly ? [] : next.objects.map(\.frame)
        }
        let old = Dictionary(uniqueKeysWithValues: previous.objects.map { ($0.id, $0) })
        let new = Dictionary(uniqueKeysWithValues: next.objects.map { ($0.id, $0) })
        return Set(old.keys).union(new.keys).sorted { $0.description < $1.description }.flatMap { id -> [WorldRect] in
            guard old[id] != new[id] else { return [] }
            return [old[id]?.frame, new[id]?.frame].compactMap { $0 }
        }
    }

    private func contains(_ rect: WorldRect, _ point: WorldPoint) -> Bool {
        point.x >= rect.minX && point.y >= rect.minY && point.x <= rect.maxX && point.y <= rect.maxY
    }

    private func intersects(_ lhs: WorldRect, _ rhs: WorldRect) -> Bool {
        lhs.minX < rhs.maxX && lhs.maxX > rhs.minX && lhs.minY < rhs.maxY && lhs.maxY > rhs.minY
    }

    private func isInsideClip(_ object: CanvasRenderObject, point: WorldPoint? = nil) -> Bool {
        guard let clip = object.clipRect else { return true }
        return point.map { contains(clip, $0) } ?? intersects(object.frame, clip)
    }

    private func accessibilityID(for id: NodeID) -> CanvasAccessibilityID {
        CanvasAccessibilityID(id.rawValue)
    }

    private func digest(_ objects: [CanvasRenderObject]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(objects.sorted {
            $0.paintOrder == $1.paintOrder ? $0.id.description < $1.id.description : $0.paintOrder < $1.paintOrder
        })) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct CanvasRenderAdoptionGate: Sendable {
    func validate(_ plan: CanvasRenderPlan, expected: CanvasRenderRequestIdentity) throws {
        guard plan.identity == expected else { throw CanvasRendererError.staleResult }
    }
}

struct CanvasRenderDisplayState: Sendable {
    private(set) var lastValidPlan: CanvasRenderPlan?

    mutating func adopt(_ plan: CanvasRenderPlan, expected: CanvasRenderRequestIdentity) throws {
        try CanvasRenderAdoptionGate().validate(plan, expected: expected)
        lastValidPlan = plan
    }
}

actor CanvasRenderWorker {
    private let core = CanvasRendererCore()
    func prepare(
        scene: CanvasRenderSceneSnapshot,
        overlays: CanvasEditorOverlaySnapshot,
        viewport: CanvasViewportState,
        previous: CanvasRenderSceneSnapshot? = nil
    ) throws -> CanvasRenderPlan {
        try core.prepare(
            scene: scene,
            overlays: overlays,
            viewport: viewport,
            previous: previous,
            cancellation: CanvasRenderCancellation { _ in Task<Never, Never>.isCancelled }
        )
    }
}

struct CanvasRenderCache: Sendable {
    private(set) var entries: [CanvasRenderRequestIdentity: [CanvasRenderTile]] = [:]
    private(set) var order: [CanvasRenderRequestIdentity] = []

    mutating func insert(_ plan: CanvasRenderPlan) {
        entries[plan.identity] = plan.tiles
        order.removeAll { $0 == plan.identity }
        order.append(plan.identity)
        while order.count > CanvasRendererPolicy.maximumRetainedGenerations {
            let evicted = order.removeFirst()
            entries.removeValue(forKey: evicted)
        }
    }
}

enum CanvasRenderDiagnosticResult: String, Codable, Sendable { case success, failure, cancelled, stale }
struct CanvasRenderDiagnosticRecord: Codable, Equatable, Sendable {
    let requirementID: String
    let operation: String
    let surfaceIdentifier: String
    let generation: UInt64
    let durationMilliseconds: Double
    let invalidation: CanvasInvalidationKind?
    let tileCount: Int
    let cacheBytes: Int
    let frameCount: Int
    let stallCount: Int
    let result: CanvasRenderDiagnosticResult
    let failureCategory: String?
}

actor CanvasRenderDiagnostics {
    private var records: [CanvasRenderDiagnosticRecord] = []
    func append(_ record: CanvasRenderDiagnosticRecord) { records.append(record) }
    func snapshot() -> [CanvasRenderDiagnosticRecord] { records }
}

enum CanvasRenderDiagnosticFactory {
    static func make(
        operation: String,
        plan: CanvasRenderPlan?,
        identity: CanvasRenderRequestIdentity,
        surfaceID: CanvasRenderSurfaceID,
        durationMilliseconds: Double,
        result: CanvasRenderDiagnosticResult,
        failureCategory: String? = nil
    ) -> CanvasRenderDiagnosticRecord {
        let tiles = plan?.tiles ?? []
        return CanvasRenderDiagnosticRecord(
            requirementID: "SF-0407-008",
            operation: operation,
            surfaceIdentifier: String(surfaceID.description.prefix(8)),
            generation: identity.viewportGeneration,
            durationMilliseconds: max(0, durationMilliseconds),
            invalidation: plan?.invalidation,
            tileCount: tiles.count,
            cacheBytes: tiles.reduce(0) { $0 + $1.estimatedBytes },
            frameCount: 0,
            stallCount: 0,
            result: result,
            failureCategory: failureCategory.map { String($0.prefix(64)) }
        )
    }
}
