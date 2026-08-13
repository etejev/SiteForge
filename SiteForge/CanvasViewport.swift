import Foundation

protocol CanvasCoordinateSpace: Sendable {}
enum WorldCoordinateSpace: CanvasCoordinateSpace {}
enum ViewportCoordinateSpace: CanvasCoordinateSpace {}
enum DeviceCoordinateSpace: CanvasCoordinateSpace {}

struct CanvasPoint<Space: CanvasCoordinateSpace>: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    var isFinite: Bool { x.isFinite && y.isFinite }
}

struct CanvasSize<Space: CanvasCoordinateSpace>: Codable, Hashable, Sendable {
    var width: Double
    var height: Double

    init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    var isValid: Bool {
        width.isFinite && height.isFinite && width > 0 && height > 0
    }
}

struct CanvasVector<Space: CanvasCoordinateSpace>: Codable, Hashable, Sendable {
    var dx: Double
    var dy: Double

    init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }

    var isFinite: Bool { dx.isFinite && dy.isFinite }
}

struct CanvasRect<Space: CanvasCoordinateSpace>: Codable, Hashable, Sendable {
    var origin: CanvasPoint<Space>
    var size: CanvasSize<Space>

    init(origin: CanvasPoint<Space>, size: CanvasSize<Space>) {
        self.origin = origin
        self.size = size
    }

    var minX: Double { origin.x }
    var minY: Double { origin.y }
    var maxX: Double { origin.x + size.width }
    var maxY: Double { origin.y + size.height }
    var isValid: Bool { origin.isFinite && size.isValid && maxX.isFinite && maxY.isFinite }
}

typealias WorldPoint = CanvasPoint<WorldCoordinateSpace>
typealias WorldSize = CanvasSize<WorldCoordinateSpace>
typealias WorldVector = CanvasVector<WorldCoordinateSpace>
typealias WorldRect = CanvasRect<WorldCoordinateSpace>
typealias ViewportPoint = CanvasPoint<ViewportCoordinateSpace>
typealias ViewportSize = CanvasSize<ViewportCoordinateSpace>
typealias ViewportVector = CanvasVector<ViewportCoordinateSpace>
typealias ViewportRect = CanvasRect<ViewportCoordinateSpace>
typealias DevicePoint = CanvasPoint<DeviceCoordinateSpace>
typealias DeviceSize = CanvasSize<DeviceCoordinateSpace>
typealias DeviceRect = CanvasRect<DeviceCoordinateSpace>

enum CanvasViewportError: Error, Equatable, LocalizedError, Sendable {
    case nonfiniteValue
    case invalidSize
    case invalidZoom
    case invalidPixelRatio
    case overflow
    case cancelled
    case staleResult

    var errorDescription: String? {
        switch self {
        case .nonfiniteValue: "A viewport value was not finite. Reset the viewport and try again."
        case .invalidSize: "The viewport or world bounds have an invalid size. Restore a valid window size and try again."
        case .invalidZoom: "That zoom level is unavailable. Choose a value between 25% and 800%."
        case .invalidPixelRatio: "The display scale is unavailable. Move the window to a valid display and try again."
        case .overflow: "The requested coordinate is outside the supported canvas range. Reset or fit the viewport."
        case .cancelled: "Viewport preparation was cancelled. The last valid viewport remains active."
        case .staleResult: "A newer viewport superseded this result."
        }
    }
}

struct CanvasZoom: Codable, Hashable, Comparable, Sendable {
    static let minimum = CanvasZoom(unchecked: 0.25)
    static let maximum = CanvasZoom(unchecked: 8)
    static let actualSize = CanvasZoom(unchecked: 1)

    let value: Double

    init(_ value: Double) throws {
        guard value.isFinite else { throw CanvasViewportError.nonfiniteValue }
        guard Self.minimum.value...Self.maximum.value ~= value else {
            throw CanvasViewportError.invalidZoom
        }
        self.value = value
    }

    private init(unchecked value: Double) { self.value = value }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }

    static func clamped(_ value: Double) throws -> Self {
        guard value.isFinite else { throw CanvasViewportError.nonfiniteValue }
        return CanvasZoom(unchecked: min(maximum.value, max(minimum.value, value)))
    }

    var percent: Int { Int((value * 100).rounded()) }
}

struct CanvasPixelRatio: Codable, Hashable, Sendable {
    static let supportedRange = 0.5...4.0
    let value: Double

    init(_ value: Double) throws {
        guard value.isFinite else { throw CanvasViewportError.nonfiniteValue }
        guard Self.supportedRange.contains(value) else { throw CanvasViewportError.invalidPixelRatio }
        self.value = value
    }
}

struct CanvasCoordinateTransform: Codable, Hashable, Sendable {
    static let reversibleTolerance = 1e-8
    static let maximumMagnitude = 1e12

    let worldOrigin: WorldPoint
    let zoom: CanvasZoom
    let pixelRatio: CanvasPixelRatio

    init(worldOrigin: WorldPoint, zoom: CanvasZoom, pixelRatio: CanvasPixelRatio) throws {
        guard worldOrigin.isFinite else { throw CanvasViewportError.nonfiniteValue }
        guard abs(worldOrigin.x) <= Self.maximumMagnitude,
              abs(worldOrigin.y) <= Self.maximumMagnitude else { throw CanvasViewportError.overflow }
        self.worldOrigin = worldOrigin
        self.zoom = zoom
        self.pixelRatio = pixelRatio
    }

    func worldToViewport(_ point: WorldPoint) throws -> ViewportPoint {
        guard point.isFinite else { throw CanvasViewportError.nonfiniteValue }
        let result = ViewportPoint(
            x: (point.x - worldOrigin.x) * zoom.value,
            y: (point.y - worldOrigin.y) * zoom.value
        )
        try validateMagnitude(result.x, result.y)
        return result
    }

    func viewportToWorld(_ point: ViewportPoint) throws -> WorldPoint {
        guard point.isFinite else { throw CanvasViewportError.nonfiniteValue }
        let result = WorldPoint(
            x: point.x / zoom.value + worldOrigin.x,
            y: point.y / zoom.value + worldOrigin.y
        )
        try validateMagnitude(result.x, result.y)
        return result
    }

    func viewportToDevice(_ point: ViewportPoint) throws -> DevicePoint {
        guard point.isFinite else { throw CanvasViewportError.nonfiniteValue }
        let result = DevicePoint(x: point.x * pixelRatio.value, y: point.y * pixelRatio.value)
        try validateMagnitude(result.x, result.y)
        return result
    }

    func deviceToViewport(_ point: DevicePoint) throws -> ViewportPoint {
        guard point.isFinite else { throw CanvasViewportError.nonfiniteValue }
        let result = ViewportPoint(x: point.x / pixelRatio.value, y: point.y / pixelRatio.value)
        try validateMagnitude(result.x, result.y)
        return result
    }

    func worldToDevice(_ point: WorldPoint) throws -> DevicePoint {
        try viewportToDevice(worldToViewport(point))
    }

    func deviceToWorld(_ point: DevicePoint) throws -> WorldPoint {
        try viewportToWorld(deviceToViewport(point))
    }

    func pixelAligned(_ point: ViewportPoint) throws -> ViewportPoint {
        let device = try viewportToDevice(point)
        return try deviceToViewport(DevicePoint(
            x: device.x.rounded(.toNearestOrEven),
            y: device.y.rounded(.toNearestOrEven)
        ))
    }

    private func validateMagnitude(_ values: Double...) throws {
        guard values.allSatisfy(\.isFinite) else { throw CanvasViewportError.nonfiniteValue }
        guard values.allSatisfy({ abs($0) <= Self.maximumMagnitude }) else {
            throw CanvasViewportError.overflow
        }
    }
}

enum CanvasFitPolicy: String, Codable, CaseIterable, Sendable {
    case none
    case fitDocument
    case fitWidth
}

enum CanvasViewportIdentityDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "viewport-scene"
}
typealias CanvasViewportSceneID = StableIdentifier<CanvasViewportIdentityDomain>

struct CanvasViewportState: Codable, Equatable, Sendable {
    static let panPadding: Double = 2_048
    static let keyboardPanStep: Double = 64

    let sceneID: CanvasViewportSceneID
    private(set) var generation: UInt64
    private(set) var worldOrigin: WorldPoint
    private(set) var viewportSize: ViewportSize
    private(set) var contentBounds: WorldRect
    private(set) var zoom: CanvasZoom
    private(set) var pixelRatio: CanvasPixelRatio
    private(set) var fitPolicy: CanvasFitPolicy

    init(
        sceneID: CanvasViewportSceneID = CanvasViewportSceneID(),
        generation: UInt64 = 0,
        worldOrigin: WorldPoint = WorldPoint(x: -128, y: -96),
        viewportSize: ViewportSize = ViewportSize(width: 680, height: 440),
        contentBounds: WorldRect = WorldRect(
            origin: WorldPoint(x: 0, y: 0),
            size: WorldSize(width: 1_440, height: 900)
        ),
        zoom: CanvasZoom = .actualSize,
        pixelRatio: CanvasPixelRatio = try! CanvasPixelRatio(2),
        fitPolicy: CanvasFitPolicy = .none
    ) throws {
        guard viewportSize.isValid, contentBounds.isValid else { throw CanvasViewportError.invalidSize }
        self.sceneID = sceneID
        self.generation = generation
        self.worldOrigin = worldOrigin
        self.viewportSize = viewportSize
        self.contentBounds = contentBounds
        self.zoom = zoom
        self.pixelRatio = pixelRatio
        self.fitPolicy = fitPolicy
        try validateOrigin(worldOrigin)
        self.worldOrigin = boundedOrigin(worldOrigin, zoom: zoom, viewportSize: viewportSize)
    }

    var transform: CanvasCoordinateTransform {
        // Every mutation validates these values before commit.
        try! CanvasCoordinateTransform(worldOrigin: worldOrigin, zoom: zoom, pixelRatio: pixelRatio)
    }

    var visibleWorldRect: WorldRect {
        WorldRect(
            origin: worldOrigin,
            size: WorldSize(
                width: viewportSize.width / zoom.value,
                height: viewportSize.height / zoom.value
            )
        )
    }

    mutating func zoom(to requested: Double, around anchor: ViewportPoint) throws {
        guard anchor.isFinite else { throw CanvasViewportError.nonfiniteValue }
        let nextZoom = try CanvasZoom.clamped(requested)
        let anchorWorld = try transform.viewportToWorld(anchor)
        let proposed = WorldPoint(
            x: anchorWorld.x - anchor.x / nextZoom.value,
            y: anchorWorld.y - anchor.y / nextZoom.value
        )
        try commit(origin: proposed, zoom: nextZoom, fitPolicy: .none)
    }

    mutating func zoomBy(factor: Double, around anchor: ViewportPoint) throws {
        guard factor.isFinite, factor > 0 else { throw CanvasViewportError.invalidZoom }
        try zoom(to: zoom.value * factor, around: anchor)
    }

    mutating func pan(by delta: ViewportVector) throws {
        guard delta.isFinite else { throw CanvasViewportError.nonfiniteValue }
        let proposed = WorldPoint(
            x: worldOrigin.x - delta.dx / zoom.value,
            y: worldOrigin.y - delta.dy / zoom.value
        )
        try commit(origin: proposed, zoom: zoom, fitPolicy: .none)
    }

    mutating func resize(to size: ViewportSize, pixelRatio: Double? = nil) throws {
        guard size.isValid else { throw CanvasViewportError.invalidSize }
        let oldCenter = try transform.viewportToWorld(ViewportPoint(
            x: viewportSize.width / 2,
            y: viewportSize.height / 2
        ))
        let nextRatio = try pixelRatio.map(CanvasPixelRatio.init) ?? self.pixelRatio
        viewportSize = size
        self.pixelRatio = nextRatio
        switch fitPolicy {
        case .none:
            let proposed = WorldPoint(
                x: oldCenter.x - size.width / (2 * zoom.value),
                y: oldCenter.y - size.height / (2 * zoom.value)
            )
            worldOrigin = boundedOrigin(proposed, zoom: zoom, viewportSize: size)
            incrementGeneration()
        case .fitDocument, .fitWidth:
            try fit(fitPolicy)
        }
    }

    mutating func reset() throws {
        try commit(origin: WorldPoint(x: -128, y: -96), zoom: .actualSize, fitPolicy: .none)
    }

    /// Centers the canonical pasteboard at the current zoom without changing
    /// authored coordinates or selecting a user-visible fit command.
    mutating func centerContent() throws {
        let visibleWidth = viewportSize.width / zoom.value
        let visibleHeight = viewportSize.height / zoom.value
        try commit(
            origin: WorldPoint(
                x: contentBounds.origin.x - (visibleWidth - contentBounds.size.width) / 2,
                y: contentBounds.origin.y - (visibleHeight - contentBounds.size.height) / 2
            ),
            zoom: zoom,
            fitPolicy: .none
        )
    }

    mutating func fit(_ policy: CanvasFitPolicy) throws {
        guard policy != .none else {
            fitPolicy = .none
            incrementGeneration()
            return
        }
        let inset: Double = 48
        let availableWidth = max(1, viewportSize.width - inset * 2)
        let availableHeight = max(1, viewportSize.height - inset * 2)
        let rawZoom: Double
        switch policy {
        case .none: rawZoom = zoom.value
        case .fitDocument:
            rawZoom = min(availableWidth / contentBounds.size.width, availableHeight / contentBounds.size.height)
        case .fitWidth:
            rawZoom = availableWidth / contentBounds.size.width
        }
        let nextZoom = try CanvasZoom.clamped(rawZoom)
        let visibleWidth = viewportSize.width / nextZoom.value
        let visibleHeight = viewportSize.height / nextZoom.value
        let proposed = WorldPoint(
            x: contentBounds.origin.x - (visibleWidth - contentBounds.size.width) / 2,
            y: policy == .fitDocument
                ? contentBounds.origin.y - (visibleHeight - contentBounds.size.height) / 2
                : contentBounds.origin.y - inset / nextZoom.value
        )
        try commit(origin: proposed, zoom: nextZoom, fitPolicy: policy)
    }

    mutating func setContentBounds(_ bounds: WorldRect) throws {
        guard bounds.isValid else { throw CanvasViewportError.invalidSize }
        contentBounds = bounds
        if fitPolicy == .none {
            worldOrigin = boundedOrigin(worldOrigin, zoom: zoom, viewportSize: viewportSize)
            incrementGeneration()
        } else {
            try fit(fitPolicy)
        }
    }

    private mutating func commit(origin: WorldPoint, zoom: CanvasZoom, fitPolicy: CanvasFitPolicy) throws {
        try validateOrigin(origin)
        self.zoom = zoom
        self.fitPolicy = fitPolicy
        worldOrigin = boundedOrigin(origin, zoom: zoom, viewportSize: viewportSize)
        incrementGeneration()
    }

    private func validateOrigin(_ origin: WorldPoint) throws {
        guard origin.isFinite else { throw CanvasViewportError.nonfiniteValue }
        guard abs(origin.x) <= CanvasCoordinateTransform.maximumMagnitude,
              abs(origin.y) <= CanvasCoordinateTransform.maximumMagnitude else {
            throw CanvasViewportError.overflow
        }
    }

    private func boundedOrigin(
        _ proposed: WorldPoint,
        zoom: CanvasZoom,
        viewportSize: ViewportSize
    ) -> WorldPoint {
        let visibleWidth = viewportSize.width / zoom.value
        let visibleHeight = viewportSize.height / zoom.value
        let minX = contentBounds.minX - Self.panPadding
        let minY = contentBounds.minY - Self.panPadding
        let maxX = max(minX, contentBounds.maxX + Self.panPadding - visibleWidth)
        let maxY = max(minY, contentBounds.maxY + Self.panPadding - visibleHeight)
        return WorldPoint(
            x: min(maxX, max(minX, proposed.x)),
            y: min(maxY, max(minY, proposed.y))
        )
    }

    private mutating func incrementGeneration() {
        generation = generation == UInt64.max ? 0 : generation + 1
    }
}

enum CanvasViewportCommandName: String, CaseIterable, Codable, Sendable {
    case zoomIn, zoomOut, actualSize, fitDocument, fitWidth
    case panLeft, panRight, panUp, panDown
}

struct CanvasViewportCommand: Codable, Equatable, Sendable {
    let name: CanvasViewportCommandName
    let anchor: ViewportPoint?

    init(_ name: CanvasViewportCommandName, anchor: ViewportPoint? = nil) {
        self.name = name
        self.anchor = anchor
    }
}

struct CanvasViewportCommandRegistry: Sendable {
    func isEnabled(_ command: CanvasViewportCommand, in state: CanvasViewportState) -> Bool {
        switch command.name {
        case .zoomIn: state.zoom < .maximum
        case .zoomOut: state.zoom > .minimum
        default: true
        }
    }

    func apply(_ command: CanvasViewportCommand, to state: inout CanvasViewportState) throws {
        guard isEnabled(command, in: state) else { throw CanvasViewportError.invalidZoom }
        let center = command.anchor ?? ViewportPoint(
            x: state.viewportSize.width / 2,
            y: state.viewportSize.height / 2
        )
        switch command.name {
        case .zoomIn: try state.zoomBy(factor: 1.25, around: center)
        case .zoomOut: try state.zoomBy(factor: 0.8, around: center)
        case .actualSize: try state.reset()
        case .fitDocument: try state.fit(.fitDocument)
        case .fitWidth: try state.fit(.fitWidth)
        case .panLeft: try state.pan(by: ViewportVector(dx: CanvasViewportState.keyboardPanStep, dy: 0))
        case .panRight: try state.pan(by: ViewportVector(dx: -CanvasViewportState.keyboardPanStep, dy: 0))
        case .panUp: try state.pan(by: ViewportVector(dx: 0, dy: CanvasViewportState.keyboardPanStep))
        case .panDown: try state.pan(by: ViewportVector(dx: 0, dy: -CanvasViewportState.keyboardPanStep))
        }
    }
}

struct CanvasViewportOperationIdentity: Codable, Equatable, Sendable {
    let documentID: DocumentID
    let revision: UInt64
    let sceneID: CanvasViewportSceneID
    let generation: UInt64
}

struct CanvasViewportSceneObject: Codable, Equatable, Sendable {
    let id: NodeID
    let bounds: WorldRect
}

struct CanvasViewportPreparationRequest: Sendable {
    let identity: CanvasViewportOperationIdentity
    let viewport: CanvasViewportState
    let objects: [CanvasViewportSceneObject]
}

struct PreparedCanvasViewportScene: Equatable, Sendable {
    let identity: CanvasViewportOperationIdentity
    let objectCount: Int
    let deterministicDigest: String
}

struct CanvasViewportCancellation: Sendable {
    let isCancelled: @Sendable () -> Bool
    static let never = CanvasViewportCancellation(isCancelled: { false })
}

actor CanvasViewportScenePreparer {
    func prepare(
        _ request: CanvasViewportPreparationRequest,
        cancellation: CanvasViewportCancellation = .never
    ) throws -> PreparedCanvasViewportScene {
        var digest: UInt64 = 1_469_598_103_934_665_603
        let transform = request.viewport.transform
        for (index, object) in request.objects.enumerated() {
            if index.isMultiple(of: 64), cancellation.isCancelled() {
                throw CanvasViewportError.cancelled
            }
            guard object.bounds.isValid else { throw CanvasViewportError.invalidSize }
            let origin = try transform.worldToViewport(object.bounds.origin)
            let values = [
                origin.x,
                origin.y,
                object.bounds.size.width * request.viewport.zoom.value,
                object.bounds.size.height * request.viewport.zoom.value,
            ]
            for value in values {
                digest ^= value.bitPattern
                digest &*= 1_099_511_628_211
            }
            for byte in object.id.description.utf8 {
                digest ^= UInt64(byte)
                digest &*= 1_099_511_628_211
            }
        }
        guard !cancellation.isCancelled() else { throw CanvasViewportError.cancelled }
        return PreparedCanvasViewportScene(
            identity: request.identity,
            objectCount: request.objects.count,
            deterministicDigest: String(digest, radix: 16)
        )
    }
}

struct CanvasViewportAdoptionGate: Sendable {
    func validate(
        _ result: PreparedCanvasViewportScene,
        expected: CanvasViewportOperationIdentity
    ) throws {
        guard result.identity == expected else { throw CanvasViewportError.staleResult }
    }
}

enum CanvasViewportDiagnosticResult: String, Codable, Sendable {
    case success, failure, cancelled, stale
}

struct CanvasViewportDiagnosticRecord: Codable, Equatable, Sendable {
    let requirementID: String
    let operation: CanvasViewportCommandName
    let sceneIdentifier: String
    let generation: UInt64
    let durationMilliseconds: Double
    let result: CanvasViewportDiagnosticResult
    let failureCategory: String?
}

actor CanvasViewportDiagnostics {
    private var records: [CanvasViewportDiagnosticRecord] = []
    func append(_ record: CanvasViewportDiagnosticRecord) { records.append(record) }
    func snapshot() -> [CanvasViewportDiagnosticRecord] { records }
}
