import CryptoKit
import Foundation

// SF-0403-001...008 — bounded deterministic move/resize geometry transforms.

enum TransformSessionIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "transform-session"
}
typealias TransformSessionID = StableIdentifier<TransformSessionIdentifierDomain>

enum TransformHandle: String, Codable, CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

enum TransformAxisConstraint: String, Codable, Sendable {
    case none, horizontal, vertical
}

enum TransformProvenance: String, Codable, CaseIterable, Sendable {
    case pointer, keyboard, menu, contextualMenu, accessibility, automation
}

enum TransformOperation: Equatable, Sendable {
    case move(delta: WorldVector, constraint: TransformAxisConstraint)
    case resize(handle: TransformHandle, delta: WorldVector, constraint: TransformAxisConstraint)

    var name: String {
        switch self {
        case .move: "move"
        case .resize: "resize"
        }
    }
}

struct TransformOperationIdentity: Equatable, Sendable {
    let sessionID: TransformSessionID
    let documentID: DocumentID
    let pageID: PageID
    let revision: UInt64
    let sceneID: CanvasViewportSceneID
    let rendererGeneration: UInt64
}

struct GeometryTransformCommand: Equatable, Sendable {
    let identity: TransformOperationIdentity
    let orderedNodeIDs: [NodeID]
    let operation: TransformOperation
    let provenance: TransformProvenance
}

struct TransformValidationContext: Sendable {
    let activePageID: PageID
    let currentSceneID: CanvasViewportSceneID
    let rendererGeneration: UInt64
    let selectedNodeIDs: [NodeID]
    let availableNodeIDs: Set<NodeID>
    let isLifecycleAvailable: Bool
    let lifecycleDisabledReason: String?
}

enum TransformError: Error, Equatable, LocalizedError, Sendable {
    case lifecycleUnavailable(String)
    case emptySelection
    case duplicateTarget
    case staleDocument
    case staleRevision
    case revisionExhausted
    case staleRenderer
    case pageUnavailable
    case crossPageTarget
    case selectionMismatch
    case missingTarget
    case lockedTarget
    case hiddenTarget
    case unavailableTarget
    case incompatibleGeometry
    case incompatibleMultipleResize
    case invalidDelta
    case invalidResult
    case cancelled

    var errorDescription: String? {
        switch self {
        case .lifecycleUnavailable(let reason): reason
        case .emptySelection: "Select a transformable object before moving or resizing."
        case .duplicateTarget: "A transform cannot contain the same stable object identity twice."
        case .staleDocument: "A different document now owns this transform."
        case .staleRevision: "The document changed before the transform could commit."
        case .revisionExhausted: "The document revision cannot accept another transform."
        case .staleRenderer: "A newer rendered scene replaced this transform."
        case .pageUnavailable: "The active transform page is no longer available."
        case .crossPageTarget: "All transformed objects must belong to the active page."
        case .selectionMismatch: "The ordered selection changed before the transform could commit."
        case .missingTarget: "A selected transform object no longer exists."
        case .lockedTarget: "Locked objects can be inspected but cannot be transformed."
        case .hiddenTarget: "Hidden objects cannot be transformed."
        case .unavailableTarget: "An object is unavailable in the current rendered scene."
        case .incompatibleGeometry: "Every target must have explicit finite authored geometry."
        case .incompatibleMultipleResize: "Resize one object at a time; multiple-selection resize is not supported by this bounded slice."
        case .invalidDelta: "Transform values must be finite and within the supported geometry range."
        case .invalidResult: "The requested transform would produce invalid geometry."
        case .cancelled: "The transform was cancelled; committed geometry is unchanged."
        }
    }
}

struct TransformAvailability: Equatable, Sendable {
    let isEnabled: Bool
    let disabledReason: String?

    static let enabled = Self(isEnabled: true, disabledReason: nil)
    static func disabled(_ reason: String) -> Self {
        Self(isEnabled: false, disabledReason: reason)
    }
}

struct TransformCancellation: Sendable {
    let isCancelled: @Sendable () -> Bool
    static let never = Self(isCancelled: { false })
}

struct TransformGeometry: Codable, Equatable, Sendable {
    let nodeID: NodeID
    let original: WorldRect
    let preview: WorldRect
}

struct PreparedTransform: Equatable, Sendable {
    let identity: TransformOperationIdentity
    let operation: TransformOperation
    let geometries: [TransformGeometry]
    let documentCommand: DocumentCommand
}

enum TransformPolicy {
    static let minimumDimension = 1.0
    static let keyboardStep = 1.0
    static let keyboardLargeStep = 10.0
    static let handleHitRadius = 10.0
}

struct TransformCommandRegistry: Sendable {
    static let requirementIDs: Set<String> = [
        "SF-0403-001", "SF-0403-002", "SF-0403-003", "SF-0403-004",
        "SF-0403-005", "SF-0403-006", "SF-0403-007", "SF-0403-008",
    ]

    func availability(
        for command: GeometryTransformCommand,
        in document: CanonicalDocument,
        context: TransformValidationContext
    ) -> TransformAvailability {
        do {
            _ = try prepare(command, in: document, context: context)
            return .enabled
        } catch {
            return .disabled(error.localizedDescription)
        }
    }

    func prepare(
        _ command: GeometryTransformCommand,
        in document: CanonicalDocument,
        context: TransformValidationContext,
        cancellation: TransformCancellation = .never
    ) throws -> PreparedTransform {
        guard !cancellation.isCancelled() else { throw TransformError.cancelled }
        guard context.isLifecycleAvailable else {
            throw TransformError.lifecycleUnavailable(
                context.lifecycleDisabledReason ?? "Transforms are unavailable during the current document operation."
            )
        }
        guard command.identity.documentID == document.id else { throw TransformError.staleDocument }
        guard command.identity.revision == document.revision else { throw TransformError.staleRevision }
        guard document.revision < UInt64.max else { throw TransformError.revisionExhausted }
        guard command.identity.pageID == context.activePageID,
              let page = document.pages.first(where: { $0.id == context.activePageID }) else {
            throw TransformError.pageUnavailable
        }
        guard command.identity.sceneID == context.currentSceneID,
              command.identity.rendererGeneration == context.rendererGeneration else {
            throw TransformError.staleRenderer
        }
        guard !command.orderedNodeIDs.isEmpty else { throw TransformError.emptySelection }
        guard Set(command.orderedNodeIDs).count == command.orderedNodeIDs.count else {
            throw TransformError.duplicateTarget
        }
        guard command.orderedNodeIDs == context.selectedNodeIDs else {
            throw TransformError.selectionMismatch
        }
        if case .resize = command.operation, command.orderedNodeIDs.count != 1 {
            throw TransformError.incompatibleMultipleResize
        }
        try validateOperation(command.operation)

        var geometries: [TransformGeometry] = []
        geometries.reserveCapacity(command.orderedNodeIDs.count)
        var mutations: [DocumentCommand] = []
        mutations.reserveCapacity(command.orderedNodeIDs.count * 4)
        for id in command.orderedNodeIDs {
            guard !cancellation.isCancelled() else { throw TransformError.cancelled }
            guard let node = page.nodes.first(where: { $0.id == id }) else {
                if document.pages.drop(while: { $0.id != page.id }).dropFirst().contains(where: {
                    $0.nodes.contains(where: { $0.id == id })
                }) || document.pages.prefix(while: { $0.id != page.id }).contains(where: {
                    $0.nodes.contains(where: { $0.id == id })
                }) {
                    throw TransformError.crossPageTarget
                }
                throw TransformError.missingTarget
            }
            guard !node.insertionBooleanProperty("locked") else { throw TransformError.lockedTarget }
            guard !node.insertionBooleanProperty("hidden") else { throw TransformError.hiddenTarget }
            guard context.availableNodeIDs.contains(id) else { throw TransformError.unavailableTarget }
            guard let original = node.insertionGeometry?.frame else {
                throw TransformError.incompatibleGeometry
            }
            let preview = try Self.resolve(original, operation: command.operation)
            geometries.append(TransformGeometry(nodeID: id, original: original, preview: preview))
            mutations.append(contentsOf: try propertyCommands(
                pageID: page.id, node: node, frame: preview, operation: command.operation
            ))
        }
        guard !cancellation.isCancelled() else { throw TransformError.cancelled }
        let documentCommand = DocumentCommand.batch(mutations)
        guard CommandRegistry().availability(for: documentCommand, in: document).isEnabled else {
            throw TransformError.invalidResult
        }
        return PreparedTransform(
            identity: command.identity,
            operation: command.operation,
            geometries: geometries,
            documentCommand: documentCommand
        )
    }

    static func resolve(_ frame: WorldRect, operation: TransformOperation) throws -> WorldRect {
        guard frame.isValid else { throw TransformError.incompatibleGeometry }
        switch operation {
        case .move(let rawDelta, let constraint):
            let delta = constrained(rawDelta, constraint: constraint)
            return try validated(WorldRect(
                origin: WorldPoint(x: frame.origin.x + delta.dx, y: frame.origin.y + delta.dy),
                size: frame.size
            ))
        case .resize(let handle, let rawDelta, let constraint):
            let delta = constrained(rawDelta, constraint: constraint)
            var x = frame.origin.x
            var y = frame.origin.y
            var width = frame.size.width
            var height = frame.size.height
            if [.topLeft, .left, .bottomLeft].contains(handle) {
                x += delta.dx
                width -= delta.dx
            }
            if [.topRight, .right, .bottomRight].contains(handle) {
                width += delta.dx
            }
            if [.topLeft, .top, .topRight].contains(handle) {
                y += delta.dy
                height -= delta.dy
            }
            if [.bottomLeft, .bottom, .bottomRight].contains(handle) {
                height += delta.dy
            }
            return try validated(WorldRect(
                origin: WorldPoint(x: x, y: y),
                size: WorldSize(width: width, height: height)
            ))
        }
    }

    private static func constrained(
        _ delta: WorldVector,
        constraint: TransformAxisConstraint
    ) -> WorldVector {
        switch constraint {
        case .none: delta
        case .horizontal: WorldVector(dx: delta.dx, dy: 0)
        case .vertical: WorldVector(dx: 0, dy: delta.dy)
        }
    }

    private static func validated(_ frame: WorldRect) throws -> WorldRect {
        let values = [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height]
        guard values.allSatisfy(\.isFinite),
              abs(frame.origin.x) <= LayoutPolicy.maximumDimension,
              abs(frame.origin.y) <= LayoutPolicy.maximumDimension,
              frame.size.width >= TransformPolicy.minimumDimension,
              frame.size.height >= TransformPolicy.minimumDimension,
              frame.size.width <= LayoutPolicy.maximumDimension,
              frame.size.height <= LayoutPolicy.maximumDimension else {
            throw TransformError.invalidResult
        }
        return frame
    }

    private func validateOperation(_ operation: TransformOperation) throws {
        let delta: WorldVector
        switch operation {
        case .move(let value, _), .resize(_, let value, _): delta = value
        }
        guard delta.dx.isFinite, delta.dy.isFinite,
              abs(delta.dx) <= LayoutPolicy.maximumDimension,
              abs(delta.dy) <= LayoutPolicy.maximumDimension else {
            throw TransformError.invalidDelta
        }
    }

    private func propertyCommands(
        pageID: PageID,
        node: DocumentNode,
        frame: WorldRect,
        operation: TransformOperation
    ) throws -> [DocumentCommand] {
        let values: [(String, Double)]
        switch operation {
        case .move:
            values = [("layout.x", frame.origin.x), ("layout.y", frame.origin.y)]
        case .resize:
            values = [
                ("layout.x", frame.origin.x), ("layout.y", frame.origin.y),
                ("layout.width", frame.size.width), ("layout.height", frame.size.height),
            ]
        }
        return try values.map { key, value in
            guard let property = node.insertionProperty(key) else {
                throw TransformError.incompatibleGeometry
            }
            return .setProperty(SetPropertyCommand(
                pageID: pageID,
                nodeID: node.id,
                property: NodeProperty(
                    id: property.id,
                    key: property.key,
                    value: .number(value),
                    origin: .authored
                )
            ))
        }
    }
}

struct TransformPreview: Equatable, Sendable {
    let identity: TransformOperationIdentity
    let operation: TransformOperation
    let geometries: [TransformGeometry]
}

enum TransformSessionPhase: Equatable, Sendable {
    case inactive
    case drafting(TransformOperationIdentity)
    case previewing(TransformPreview)
    case committing(TransformPreview)
    case cancelled
    case failed(TransformError)
}

struct TransformSession: Equatable, Sendable {
    private(set) var generation: UInt64 = 0
    private(set) var phase: TransformSessionPhase = .inactive

    mutating func begin(
        documentID: DocumentID,
        pageID: PageID,
        revision: UInt64,
        sceneID: CanvasViewportSceneID,
        rendererGeneration: UInt64
    ) -> TransformOperationIdentity {
        generation &+= 1
        let identity = TransformOperationIdentity(
            sessionID: TransformSessionID(),
            documentID: documentID,
            pageID: pageID,
            revision: revision,
            sceneID: sceneID,
            rendererGeneration: rendererGeneration
        )
        phase = .drafting(identity)
        return identity
    }

    mutating func preview(_ value: TransformPreview) {
        guard currentIdentity == value.identity else { return }
        phase = .previewing(value)
    }

    mutating func beginCommit(_ value: TransformPreview) {
        guard currentIdentity == value.identity else { return }
        phase = .committing(value)
    }

    mutating func complete() {
        phase = .inactive
    }

    mutating func deactivate() {
        generation &+= 1
        phase = .inactive
    }

    mutating func cancel() {
        generation &+= 1
        phase = .cancelled
    }

    mutating func fail(_ error: TransformError) {
        phase = .failed(error)
    }

    var currentIdentity: TransformOperationIdentity? {
        switch phase {
        case .drafting(let identity): identity
        case .previewing(let preview), .committing(let preview): preview.identity
        case .inactive, .cancelled, .failed: nil
        }
    }
}

enum TransformOverlayPlanner {
    static func overlays(
        selection: SelectionState,
        renderPlan: CanvasRenderPlan,
        preview: TransformPreview?,
        handleWorldSize: Double
    ) -> [CanvasEditorOverlay] {
        let previewByID = Dictionary(
            uniqueKeysWithValues: (preview?.geometries ?? []).map { ($0.nodeID, $0.preview) }
        )
        var result = selection.orderedIDs.compactMap { id -> CanvasEditorOverlay? in
            guard let object = renderPlan.authoredObjects.first(where: { $0.id == id }) else {
                return nil
            }
            return CanvasEditorOverlay(
                id: CanvasOverlayID(derivedUUID(namespace: id.rawValue, label: "preview")),
                objectID: id,
                frame: previewByID[id] ?? object.frame,
                kind: preview == nil ? "transform-selection" : "transform-preview"
            )
        }
        guard selection.count == 1,
              let primaryID = selection.primaryID,
              let object = renderPlan.authoredObjects.first(where: { $0.id == primaryID }) else {
            return result
        }
        let frame = previewByID[primaryID] ?? object.frame
        for handle in TransformHandle.allCases {
            let point = handlePoint(handle, frame: frame)
            result.append(CanvasEditorOverlay(
                id: CanvasOverlayID(derivedUUID(namespace: primaryID.rawValue, label: handle.rawValue)),
                objectID: primaryID,
                frame: WorldRect(
                    origin: WorldPoint(
                        x: point.x - handleWorldSize / 2,
                        y: point.y - handleWorldSize / 2
                    ),
                    size: WorldSize(width: handleWorldSize, height: handleWorldSize)
                ),
                kind: "transform-handle-\(handle.rawValue)"
            ))
        }
        return result
    }

    static func hitHandle(
        at point: WorldPoint,
        frame: WorldRect,
        worldRadius: Double
    ) -> TransformHandle? {
        TransformHandle.allCases.first { handle in
            let candidate = handlePoint(handle, frame: frame)
            return abs(candidate.x - point.x) <= worldRadius
                && abs(candidate.y - point.y) <= worldRadius
        }
    }

    private static func handlePoint(_ handle: TransformHandle, frame: WorldRect) -> WorldPoint {
        let centerX = (frame.minX + frame.maxX) / 2
        let centerY = (frame.minY + frame.maxY) / 2
        return switch handle {
        case .topLeft: WorldPoint(x: frame.minX, y: frame.minY)
        case .top: WorldPoint(x: centerX, y: frame.minY)
        case .topRight: WorldPoint(x: frame.maxX, y: frame.minY)
        case .right: WorldPoint(x: frame.maxX, y: centerY)
        case .bottomRight: WorldPoint(x: frame.maxX, y: frame.maxY)
        case .bottom: WorldPoint(x: centerX, y: frame.maxY)
        case .bottomLeft: WorldPoint(x: frame.minX, y: frame.maxY)
        case .left: WorldPoint(x: frame.minX, y: centerY)
        }
    }

    private static func derivedUUID(namespace: UUID, label: String) -> UUID {
        var data = Data(namespace.uuidString.lowercased().utf8)
        data.append(Data(("transform-overlay:" + label).utf8))
        var bytes = Array(SHA256.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

enum TransformDiagnosticResult: String, Codable, Sendable {
    case success, failure, cancelled, stale
}

struct TransformDiagnosticRecord: Codable, Equatable, Sendable {
    let requirementIDs: [String]
    let operationType: String
    let provenance: TransformProvenance
    let sanitizedIdentifiers: [String]
    let durationMilliseconds: Double
    let parentRevision: UInt64
    let resultRevision: UInt64?
    let affectedObjectCount: Int
    let result: TransformDiagnosticResult
    let failureCategory: String?
}

actor TransformDiagnostics {
    private var records: [TransformDiagnosticRecord] = []
    func append(_ record: TransformDiagnosticRecord) { records.append(record) }
    func snapshot() -> [TransformDiagnosticRecord] { records }
}

enum TransformDiagnosticFactory {
    static func make(
        command: GeometryTransformCommand,
        durationMilliseconds: Double,
        resultRevision: UInt64?,
        result: TransformDiagnosticResult,
        failure: TransformError?
    ) -> TransformDiagnosticRecord {
        TransformDiagnosticRecord(
            requirementIDs: TransformCommandRegistry.requirementIDs.sorted(),
            operationType: command.operation.name,
            provenance: command.provenance,
            sanitizedIdentifiers: command.orderedNodeIDs.map(sanitize),
            durationMilliseconds: max(0, durationMilliseconds),
            parentRevision: command.identity.revision,
            resultRevision: resultRevision,
            affectedObjectCount: command.orderedNodeIDs.count,
            result: result,
            failureCategory: failure.map { String(describing: $0).prefix(64).description }
        )
    }

    private static func sanitize(_ id: NodeID) -> String {
        let digest = SHA256.hash(data: Data(("transform:" + id.description).utf8))
        return "node-" + digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}
