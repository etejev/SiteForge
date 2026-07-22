import CryptoKit
import Foundation

// SF-0501-001...008 — bounded deterministic layout-engine foundation.

struct LayoutPoint: Codable, Equatable, Hashable, Sendable {
    let x: Double
    let y: Double
}

struct LayoutSize: Codable, Equatable, Hashable, Sendable {
    let width: Double
    let height: Double
}

struct LayoutRect: Codable, Equatable, Hashable, Sendable {
    let origin: LayoutPoint
    let size: LayoutSize

    var minX: Double { origin.x }
    var minY: Double { origin.y }
    var maxX: Double { origin.x + size.width }
    var maxY: Double { origin.y + size.height }
}

enum LayoutAxis: String, Codable, CaseIterable, Sendable {
    case horizontal
    case vertical
}

enum LayoutAlignment: String, Codable, CaseIterable, Sendable {
    case start
    case center
    case end
    case stretch
    case baseline
}

enum LayoutOverflow: String, Codable, CaseIterable, Sendable {
    case visible
    case clip
    case scroll
}

enum LayoutLength: Codable, Equatable, Sendable {
    case fixed(Double)
    case intrinsic
    case fill
    case percentage(Double)
    case automatic
}

struct LayoutInsets: Codable, Equatable, Sendable {
    let top: Double
    let leading: Double
    let bottom: Double
    let trailing: Double

    init(top: Double, leading: Double, bottom: Double, trailing: Double) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    init(all value: Double) {
        self.init(top: value, leading: value, bottom: value, trailing: value)
    }

    static let zero = LayoutInsets(all: 0)
}

struct LayoutConstraints: Codable, Equatable, Sendable {
    let minWidth: Double
    let maxWidth: Double
    let minHeight: Double
    let maxHeight: Double

    init(
        minWidth: Double = 0,
        maxWidth: Double = LayoutPolicy.maximumDimension,
        minHeight: Double = 0,
        maxHeight: Double = LayoutPolicy.maximumDimension
    ) {
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.maxHeight = maxHeight
    }
}

struct LayoutIntrinsicKey: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Immutable measurements are supplied by a deterministic text/media adapter. The core never
/// invokes AppKit text shaping or reads mutable UI state while resolving geometry.
struct LayoutIntrinsicCatalog: Codable, Equatable, Sendable {
    private let entries: [LayoutIntrinsicKey: LayoutSize]

    init(entries: [LayoutIntrinsicKey: LayoutSize] = [:]) {
        self.entries = entries
    }

    func measurement(for key: LayoutIntrinsicKey) -> LayoutSize? { entries[key] }
    var orderedEntries: [(LayoutIntrinsicKey, LayoutSize)] {
        entries.keys.sorted().compactMap { key in entries[key].map { (key, $0) } }
    }
}

struct LayoutNodeSnapshot: Codable, Equatable, Identifiable, Sendable {
    let id: NodeID
    let axis: LayoutAxis?
    let width: LayoutLength
    let height: LayoutLength
    let intrinsicKey: LayoutIntrinsicKey?
    let constraints: LayoutConstraints
    let padding: LayoutInsets
    let gap: Double
    let alignment: LayoutAlignment
    let overflow: LayoutOverflow
    let childIDs: [NodeID]

    init(
        id: NodeID,
        axis: LayoutAxis? = nil,
        width: LayoutLength = .intrinsic,
        height: LayoutLength = .intrinsic,
        intrinsicKey: LayoutIntrinsicKey? = nil,
        constraints: LayoutConstraints = LayoutConstraints(),
        padding: LayoutInsets = .zero,
        gap: Double = 0,
        alignment: LayoutAlignment = .start,
        overflow: LayoutOverflow = .visible,
        childIDs: [NodeID] = []
    ) {
        self.id = id
        self.axis = axis
        self.width = width
        self.height = height
        self.intrinsicKey = intrinsicKey
        self.constraints = constraints
        self.padding = padding
        self.gap = gap
        self.alignment = alignment
        self.overflow = overflow
        self.childIDs = childIDs
    }
}

struct LayoutSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let rootID: NodeID
    let nodes: [LayoutNodeSnapshot]
    let intrinsicCatalog: LayoutIntrinsicCatalog

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        rootID: NodeID,
        nodes: [LayoutNodeSnapshot],
        intrinsicCatalog: LayoutIntrinsicCatalog = LayoutIntrinsicCatalog()
    ) {
        self.schemaVersion = schemaVersion
        self.rootID = rootID
        self.nodes = nodes
        self.intrinsicCatalog = intrinsicCatalog
    }
}

struct LayoutRequestIdentity: Codable, Equatable, Sendable {
    let documentID: DocumentID
    let revision: UInt64
    let generation: UInt64
    let viewportWidth: Double
}

struct LayoutRequest: Sendable {
    let identity: LayoutRequestIdentity
    let snapshot: LayoutSnapshot
    let containingBlock: LayoutSize
}

enum LayoutResolutionSource: String, Codable, Sendable {
    case containingBlock
    case fixed
    case intrinsic
    case fill
}

enum LayoutConstraintEffect: String, Codable, Sendable {
    case none
    case minimum
    case maximum
}

struct LayoutDimensionResolution: Codable, Equatable, Sendable {
    let source: LayoutResolutionSource
    let constraint: LayoutConstraintEffect
}

struct LayoutFragment: Codable, Equatable, Identifiable, Sendable {
    let id: NodeID
    let frame: LayoutRect
    let widthResolution: LayoutDimensionResolution
    let heightResolution: LayoutDimensionResolution
    let clippedByParent: Bool
}

struct LayoutResult: Codable, Equatable, Sendable {
    let identity: LayoutRequestIdentity
    let fragments: [LayoutFragment]
    let deterministicDigest: String

    var fragmentsByID: [NodeID: LayoutFragment] {
        Dictionary(uniqueKeysWithValues: fragments.map { ($0.id, $0) })
    }
}

enum UnsupportedLayoutSemantic: String, Codable, Equatable, Sendable {
    case percentageSizing
    case automaticSizing
    case baselineAlignment
    case scrollingOverflow
    case childrenWithoutStackAxis
}

enum LayoutFailureCategory: String, Codable, Equatable, Sendable {
    case invalidInput
    case incompatibleSchema
    case invalidGraph
    case unsupported
    case resourceLimit
    case cancelled
    case stale
}

enum LayoutEngineError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedSchema(Int)
    case emptySnapshot
    case duplicateNode(NodeID)
    case missingNode(NodeID)
    case duplicateChild(parent: NodeID, child: NodeID)
    case multipleParents(NodeID)
    case cycle(NodeID)
    case orphan(NodeID)
    case maximumDepthExceeded(NodeID)
    case nodeLimitExceeded(Int)
    case invalidValue(NodeID?)
    case impossibleConstraints(NodeID)
    case missingIntrinsicMeasurement(node: NodeID, key: LayoutIntrinsicKey?)
    case unsupported(node: NodeID, semantic: UnsupportedLayoutSemantic)
    case arithmeticOverflow(NodeID?)
    case cancelled
    case staleResult

    var failureCategory: LayoutFailureCategory {
        switch self {
        case .unsupportedSchema: .incompatibleSchema
        case .emptySnapshot, .duplicateNode, .missingNode, .duplicateChild, .multipleParents,
             .cycle, .orphan, .maximumDepthExceeded: .invalidGraph
        case .nodeLimitExceeded: .resourceLimit
        case .invalidValue, .impossibleConstraints, .missingIntrinsicMeasurement,
             .arithmeticOverflow: .invalidInput
        case .unsupported: .unsupported
        case .cancelled: .cancelled
        case .staleResult: .stale
        }
    }

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema: "This layout snapshot version is not supported. Open it with a compatible SiteForge version."
        case .emptySnapshot, .missingNode, .duplicateNode, .duplicateChild, .multipleParents,
             .cycle, .orphan, .maximumDepthExceeded:
            "The layout hierarchy is invalid. Keep the last valid layout and repair the identified objects."
        case .nodeLimitExceeded: "The layout exceeds the supported object limit. Reduce its size and retry."
        case .invalidValue, .impossibleConstraints, .arithmeticOverflow:
            "A layout value is invalid or contradictory. Correct its constraints and retry."
        case .missingIntrinsicMeasurement:
            "Intrinsic content could not be measured. Restore the dependency or choose an explicit size."
        case .unsupported:
            "This layout behavior is not supported by the current deterministic engine. Choose a supported rule."
        case .cancelled: "Layout was cancelled. The last valid layout remains active."
        case .staleResult: "A newer document revision superseded this layout result."
        }
    }
}

enum LayoutPolicy {
    static let maximumNodeCount = 20_000
    static let maximumDepth = 256
    static let maximumChildrenPerNode = 20_000
    static let maximumDimension = 1_000_000_000.0
    static let cancellationStride = 32
}

struct LayoutCancellation: Sendable {
    let isCancelled: @Sendable (Int) -> Bool
    static let never = LayoutCancellation(isCancelled: { _ in false })
}

struct DeterministicLayoutEngine: Sendable {
    static let requirementIDs: Set<String> = [
        "SF-0501-001", "SF-0501-002", "SF-0501-003", "SF-0501-004",
        "SF-0501-005", "SF-0501-006", "SF-0501-007", "SF-0501-008",
    ]

    func layout(
        _ request: LayoutRequest,
        cancellation: LayoutCancellation = .never
    ) throws -> LayoutResult {
        let graph = try ValidatedLayoutGraph(request: request, cancellation: cancellation)
        var fragments: [LayoutFragment] = []
        fragments.reserveCapacity(graph.nodes.count)
        var visited = 0
        let root = try graph.node(request.snapshot.rootID)
        let rootWidth = try resolve(
            root.width,
            intrinsic: try graph.intrinsicSize(for: root).width,
            fill: request.containingBlock.width,
            constraints: (root.constraints.minWidth, root.constraints.maxWidth),
            nodeID: root.id
        )
        let rootHeight = try resolve(
            root.height,
            intrinsic: try graph.intrinsicSize(for: root).height,
            fill: request.containingBlock.height,
            constraints: (root.constraints.minHeight, root.constraints.maxHeight),
            nodeID: root.id
        )
        let rootFrame = LayoutRect(
            origin: LayoutPoint(x: 0, y: 0),
            size: LayoutSize(width: rootWidth.value, height: rootHeight.value)
        )
        try place(
            root,
            frame: rootFrame,
            widthResolution: rootWidth.resolution,
            heightResolution: rootHeight.resolution,
            clippedByParent: false,
            graph: graph,
            fragments: &fragments,
            visited: &visited,
            cancellation: cancellation
        )
        guard !cancellation.isCancelled(visited) else { throw LayoutEngineError.cancelled }
        return LayoutResult(
            identity: request.identity,
            fragments: fragments,
            deterministicDigest: Self.digest(identity: request.identity, fragments: fragments)
        )
    }

    private func place(
        _ node: LayoutNodeSnapshot,
        frame: LayoutRect,
        widthResolution: LayoutDimensionResolution,
        heightResolution: LayoutDimensionResolution,
        clippedByParent: Bool,
        graph: ValidatedLayoutGraph,
        fragments: inout [LayoutFragment],
        visited: inout Int,
        cancellation: LayoutCancellation
    ) throws {
        visited += 1
        if visited.isMultiple(of: LayoutPolicy.cancellationStride), cancellation.isCancelled(visited) {
            throw LayoutEngineError.cancelled
        }
        fragments.append(LayoutFragment(
            id: node.id,
            frame: frame,
            widthResolution: widthResolution,
            heightResolution: heightResolution,
            clippedByParent: clippedByParent
        ))
        guard let axis = node.axis, !node.childIDs.isEmpty else { return }

        let content = try contentRect(frame: frame, padding: node.padding, nodeID: node.id)
        let availableMain = axis == .horizontal ? content.size.width : content.size.height
        let availableCross = axis == .horizontal ? content.size.height : content.size.width
        let gapTotal = try checkedProduct(node.gap, Double(max(0, node.childIDs.count - 1)), nodeID: node.id)
        var resolvedMain: [NodeID: ResolvedDimension] = [:]
        var fixedTotal = 0.0
        var fillIDs: [NodeID] = []

        for childID in node.childIDs {
            let child = try graph.node(childID)
            let rule = axis == .horizontal ? child.width : child.height
            if case .fill = rule {
                fillIDs.append(childID)
            } else {
                let intrinsic = try graph.intrinsicSize(for: child)
                let dimension = try resolve(
                    rule,
                    intrinsic: axis == .horizontal ? intrinsic.width : intrinsic.height,
                    fill: 0,
                    constraints: axis == .horizontal
                        ? (child.constraints.minWidth, child.constraints.maxWidth)
                        : (child.constraints.minHeight, child.constraints.maxHeight),
                    nodeID: child.id
                )
                resolvedMain[childID] = dimension
                fixedTotal = try checkedSum(fixedTotal, dimension.value, nodeID: node.id)
            }
        }
        let remaining = max(0, availableMain - gapTotal - fixedTotal)
        let fillShare = fillIDs.isEmpty ? 0 : remaining / Double(fillIDs.count)
        for childID in fillIDs {
            let child = try graph.node(childID)
            resolvedMain[childID] = try resolve(
                .fill,
                intrinsic: 0,
                fill: fillShare,
                constraints: axis == .horizontal
                    ? (child.constraints.minWidth, child.constraints.maxWidth)
                    : (child.constraints.minHeight, child.constraints.maxHeight),
                nodeID: child.id
            )
        }

        var cursor = axis == .horizontal ? content.minX : content.minY
        for childID in node.childIDs {
            let child = try graph.node(childID)
            let intrinsic = try graph.intrinsicSize(for: child)
            let main = try required(resolvedMain[childID], nodeID: child.id)
            var cross = try resolve(
                axis == .horizontal ? child.height : child.width,
                intrinsic: axis == .horizontal ? intrinsic.height : intrinsic.width,
                fill: availableCross,
                constraints: axis == .horizontal
                    ? (child.constraints.minHeight, child.constraints.maxHeight)
                    : (child.constraints.minWidth, child.constraints.maxWidth),
                nodeID: child.id
            )
            if node.alignment == .stretch {
                cross = constrained(
                    availableCross,
                    source: .fill,
                    minimum: axis == .horizontal ? child.constraints.minHeight : child.constraints.minWidth,
                    maximum: axis == .horizontal ? child.constraints.maxHeight : child.constraints.maxWidth
                )
            }
            let crossOffset: Double
            switch node.alignment {
            case .start, .stretch: crossOffset = 0
            case .center: crossOffset = (availableCross - cross.value) / 2
            case .end: crossOffset = availableCross - cross.value
            case .baseline:
                throw LayoutEngineError.unsupported(node: node.id, semantic: .baselineAlignment)
            }
            let childFrame: LayoutRect
            if axis == .horizontal {
                childFrame = LayoutRect(
                    origin: LayoutPoint(x: cursor, y: content.minY + crossOffset),
                    size: LayoutSize(width: main.value, height: cross.value)
                )
            } else {
                childFrame = LayoutRect(
                    origin: LayoutPoint(x: content.minX + crossOffset, y: cursor),
                    size: LayoutSize(width: cross.value, height: main.value)
                )
            }
            try validateFrame(childFrame, nodeID: child.id)
            let clipped = node.overflow == .clip && !contains(frame, childFrame)
            try place(
                child,
                frame: childFrame,
                widthResolution: axis == .horizontal ? main.resolution : cross.resolution,
                heightResolution: axis == .horizontal ? cross.resolution : main.resolution,
                clippedByParent: clipped,
                graph: graph,
                fragments: &fragments,
                visited: &visited,
                cancellation: cancellation
            )
            cursor = try checkedSum(cursor, main.value, nodeID: node.id)
            cursor = try checkedSum(cursor, node.gap, nodeID: node.id)
        }
    }

    private struct ResolvedDimension {
        let value: Double
        let resolution: LayoutDimensionResolution
    }

    private func resolve(
        _ length: LayoutLength,
        intrinsic: Double,
        fill: Double,
        constraints: (Double, Double),
        nodeID: NodeID
    ) throws -> ResolvedDimension {
        let value: Double
        let source: LayoutResolutionSource
        switch length {
        case .fixed(let fixed): value = fixed; source = .fixed
        case .intrinsic: value = intrinsic; source = .intrinsic
        case .fill: value = fill; source = .fill
        case .percentage:
            throw LayoutEngineError.unsupported(node: nodeID, semantic: .percentageSizing)
        case .automatic:
            throw LayoutEngineError.unsupported(node: nodeID, semantic: .automaticSizing)
        }
        return constrained(value, source: source, minimum: constraints.0, maximum: constraints.1)
    }

    private func constrained(
        _ value: Double,
        source: LayoutResolutionSource,
        minimum: Double,
        maximum: Double
    ) -> ResolvedDimension {
        if value < minimum {
            return ResolvedDimension(
                value: minimum,
                resolution: LayoutDimensionResolution(source: source, constraint: .minimum)
            )
        }
        if value > maximum {
            return ResolvedDimension(
                value: maximum,
                resolution: LayoutDimensionResolution(source: source, constraint: .maximum)
            )
        }
        return ResolvedDimension(
            value: value,
            resolution: LayoutDimensionResolution(source: source, constraint: .none)
        )
    }

    private func contentRect(frame: LayoutRect, padding: LayoutInsets, nodeID: NodeID) throws -> LayoutRect {
        let horizontal = try checkedSum(padding.leading, padding.trailing, nodeID: nodeID)
        let vertical = try checkedSum(padding.top, padding.bottom, nodeID: nodeID)
        let result = LayoutRect(
            origin: LayoutPoint(
                x: try checkedSum(frame.origin.x, padding.leading, nodeID: nodeID),
                y: try checkedSum(frame.origin.y, padding.top, nodeID: nodeID)
            ),
            size: LayoutSize(
                width: max(0, frame.size.width - horizontal),
                height: max(0, frame.size.height - vertical)
            )
        )
        try validateFrame(result, nodeID: nodeID)
        return result
    }

    private func checkedSum(_ lhs: Double, _ rhs: Double, nodeID: NodeID?) throws -> Double {
        let value = lhs + rhs
        guard value.isFinite, abs(value) <= LayoutPolicy.maximumDimension * 2 else {
            throw LayoutEngineError.arithmeticOverflow(nodeID)
        }
        return value
    }

    private func checkedProduct(_ lhs: Double, _ rhs: Double, nodeID: NodeID?) throws -> Double {
        let value = lhs * rhs
        guard value.isFinite, abs(value) <= LayoutPolicy.maximumDimension * 2 else {
            throw LayoutEngineError.arithmeticOverflow(nodeID)
        }
        return value
    }

    private func required(_ value: ResolvedDimension?, nodeID: NodeID) throws -> ResolvedDimension {
        guard let value else { throw LayoutEngineError.missingNode(nodeID) }
        return value
    }

    private func validateFrame(_ frame: LayoutRect, nodeID: NodeID) throws {
        let values = [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height, frame.maxX, frame.maxY]
        guard values.allSatisfy(\.isFinite), frame.size.width >= 0, frame.size.height >= 0,
              values.allSatisfy({ abs($0) <= LayoutPolicy.maximumDimension * 2 }) else {
            throw LayoutEngineError.arithmeticOverflow(nodeID)
        }
    }

    private func contains(_ outer: LayoutRect, _ inner: LayoutRect) -> Bool {
        inner.minX >= outer.minX && inner.minY >= outer.minY &&
            inner.maxX <= outer.maxX && inner.maxY <= outer.maxY
    }

    private static func digest(identity: LayoutRequestIdentity, fragments: [LayoutFragment]) -> String {
        var hash = SHA256()
        hash.update(data: Data(identity.documentID.description.utf8))
        hash.update(data: Data(withUnsafeBytes(of: identity.revision.bigEndian, Array.init)))
        hash.update(data: Data(withUnsafeBytes(of: identity.generation.bigEndian, Array.init)))
        hash.update(data: Data(withUnsafeBytes(of: identity.viewportWidth.bitPattern.bigEndian, Array.init)))
        for fragment in fragments {
            hash.update(data: Data(fragment.id.description.utf8))
            for value in [
                fragment.frame.origin.x, fragment.frame.origin.y,
                fragment.frame.size.width, fragment.frame.size.height,
            ] {
                hash.update(data: Data(withUnsafeBytes(of: value.bitPattern.bigEndian, Array.init)))
            }
            hash.update(data: Data(fragment.widthResolution.source.rawValue.utf8))
            hash.update(data: Data(fragment.widthResolution.constraint.rawValue.utf8))
            hash.update(data: Data(fragment.heightResolution.source.rawValue.utf8))
            hash.update(data: Data(fragment.heightResolution.constraint.rawValue.utf8))
            hash.update(data: Data([fragment.clippedByParent ? 1 : 0]))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private struct ValidatedLayoutGraph: Sendable {
    let nodes: [NodeID: LayoutNodeSnapshot]
    let catalog: LayoutIntrinsicCatalog

    init(request: LayoutRequest, cancellation: LayoutCancellation) throws {
        guard request.snapshot.schemaVersion == LayoutSnapshot.currentSchemaVersion else {
            throw LayoutEngineError.unsupportedSchema(request.snapshot.schemaVersion)
        }
        guard !request.snapshot.nodes.isEmpty else { throw LayoutEngineError.emptySnapshot }
        guard request.snapshot.nodes.count <= LayoutPolicy.maximumNodeCount else {
            throw LayoutEngineError.nodeLimitExceeded(request.snapshot.nodes.count)
        }
        try Self.validateSize(request.containingBlock, nodeID: nil, requiresPositive: true)
        guard request.identity.viewportWidth.isFinite,
              request.identity.viewportWidth == request.containingBlock.width else {
            throw LayoutEngineError.invalidValue(nil)
        }

        var indexed: [NodeID: LayoutNodeSnapshot] = [:]
        indexed.reserveCapacity(request.snapshot.nodes.count)
        for (offset, node) in request.snapshot.nodes.enumerated() {
            if offset.isMultiple(of: LayoutPolicy.cancellationStride), cancellation.isCancelled(offset) {
                throw LayoutEngineError.cancelled
            }
            guard indexed.updateValue(node, forKey: node.id) == nil else {
                throw LayoutEngineError.duplicateNode(node.id)
            }
            try Self.validate(node, catalog: request.snapshot.intrinsicCatalog)
        }
        guard indexed[request.snapshot.rootID] != nil else {
            throw LayoutEngineError.missingNode(request.snapshot.rootID)
        }

        var parent: [NodeID: NodeID] = [:]
        for node in request.snapshot.nodes {
            guard node.childIDs.count <= LayoutPolicy.maximumChildrenPerNode else {
                throw LayoutEngineError.nodeLimitExceeded(node.childIDs.count)
            }
            var local = Set<NodeID>()
            for childID in node.childIDs {
                guard local.insert(childID).inserted else {
                    throw LayoutEngineError.duplicateChild(parent: node.id, child: childID)
                }
                guard indexed[childID] != nil else { throw LayoutEngineError.missingNode(childID) }
                guard parent.updateValue(node.id, forKey: childID) == nil else {
                    throw LayoutEngineError.multipleParents(childID)
                }
            }
        }
        guard parent[request.snapshot.rootID] == nil else {
            throw LayoutEngineError.cycle(request.snapshot.rootID)
        }

        enum Visit { case enter(NodeID, Int), leave(NodeID) }
        var stack: [Visit] = [.enter(request.snapshot.rootID, 1)]
        var active = Set<NodeID>()
        var complete = Set<NodeID>()
        while let visit = stack.popLast() {
            switch visit {
            case .leave(let id):
                active.remove(id)
                complete.insert(id)
            case .enter(let id, let depth):
                if active.contains(id) { throw LayoutEngineError.cycle(id) }
                if complete.contains(id) { continue }
                guard depth <= LayoutPolicy.maximumDepth else {
                    throw LayoutEngineError.maximumDepthExceeded(id)
                }
                active.insert(id)
                stack.append(.leave(id))
                let children = indexed[id]?.childIDs ?? []
                for child in children.reversed() { stack.append(.enter(child, depth + 1)) }
            }
        }
        if let orphan = indexed.keys.filter({ !complete.contains($0) }).sorted(by: { $0.description < $1.description }).first {
            throw LayoutEngineError.orphan(orphan)
        }
        guard !cancellation.isCancelled(complete.count) else { throw LayoutEngineError.cancelled }
        nodes = indexed
        catalog = request.snapshot.intrinsicCatalog
    }

    func node(_ id: NodeID) throws -> LayoutNodeSnapshot {
        guard let node = nodes[id] else { throw LayoutEngineError.missingNode(id) }
        return node
    }

    func intrinsicSize(for node: LayoutNodeSnapshot) throws -> LayoutSize {
        let needsIntrinsic = node.width == .intrinsic || node.height == .intrinsic
        guard needsIntrinsic else { return LayoutSize(width: 0, height: 0) }
        guard let key = node.intrinsicKey, let size = catalog.measurement(for: key) else {
            throw LayoutEngineError.missingIntrinsicMeasurement(node: node.id, key: node.intrinsicKey)
        }
        return size
    }

    private static func validate(_ node: LayoutNodeSnapshot, catalog: LayoutIntrinsicCatalog) throws {
        let values = [
            node.constraints.minWidth, node.constraints.maxWidth,
            node.constraints.minHeight, node.constraints.maxHeight,
            node.padding.top, node.padding.leading, node.padding.bottom, node.padding.trailing,
            node.gap,
        ]
        guard values.allSatisfy(\.isFinite), values.allSatisfy({ $0 >= 0 && $0 <= LayoutPolicy.maximumDimension }) else {
            throw LayoutEngineError.invalidValue(node.id)
        }
        guard node.constraints.minWidth <= node.constraints.maxWidth,
              node.constraints.minHeight <= node.constraints.maxHeight else {
            throw LayoutEngineError.impossibleConstraints(node.id)
        }
        if !node.childIDs.isEmpty, node.axis == nil {
            throw LayoutEngineError.unsupported(node: node.id, semantic: .childrenWithoutStackAxis)
        }
        if node.alignment == .baseline {
            throw LayoutEngineError.unsupported(node: node.id, semantic: .baselineAlignment)
        }
        if node.overflow == .scroll {
            throw LayoutEngineError.unsupported(node: node.id, semantic: .scrollingOverflow)
        }
        try validate(node.width, nodeID: node.id)
        try validate(node.height, nodeID: node.id)
        if let key = node.intrinsicKey, let size = catalog.measurement(for: key) {
            try validateSize(size, nodeID: node.id, requiresPositive: false)
        }
    }

    private static func validate(_ length: LayoutLength, nodeID: NodeID) throws {
        switch length {
        case .fixed(let value):
            guard value.isFinite, value >= 0, value <= LayoutPolicy.maximumDimension else {
                throw LayoutEngineError.invalidValue(nodeID)
            }
        case .intrinsic, .fill: break
        case .percentage(let value):
            guard value.isFinite else { throw LayoutEngineError.invalidValue(nodeID) }
            throw LayoutEngineError.unsupported(node: nodeID, semantic: .percentageSizing)
        case .automatic:
            throw LayoutEngineError.unsupported(node: nodeID, semantic: .automaticSizing)
        }
    }

    private static func validateSize(_ size: LayoutSize, nodeID: NodeID?, requiresPositive: Bool) throws {
        let lowerBound = requiresPositive ? 0.0 : -Double.leastNonzeroMagnitude
        guard size.width.isFinite, size.height.isFinite,
              size.width > lowerBound, size.height > lowerBound,
              size.width <= LayoutPolicy.maximumDimension,
              size.height <= LayoutPolicy.maximumDimension else {
            throw LayoutEngineError.invalidValue(nodeID)
        }
    }
}

struct LayoutResultAdoptionGate: Sendable {
    func validate(_ result: LayoutResult, expected: LayoutRequestIdentity) throws {
        guard result.identity == expected else { throw LayoutEngineError.staleResult }
    }
}

actor LayoutEngineWorker {
    private let engine = DeterministicLayoutEngine()

    func layout(
        _ request: LayoutRequest,
        cancellation: LayoutCancellation? = nil
    ) throws -> LayoutResult {
        let effectiveCancellation = cancellation ?? LayoutCancellation { _ in
            Task<Never, Never>.isCancelled
        }
        return try engine.layout(request, cancellation: effectiveCancellation)
    }
}

enum LayoutDiagnosticOperation: String, Codable, Sendable {
    case validate
    case layout
    case adopt
}

enum LayoutDiagnosticResult: String, Codable, Sendable {
    case success
    case failure
    case cancelled
    case stale
}

struct LayoutDiagnosticRecord: Codable, Equatable, Sendable {
    let requirementID: String
    let operation: LayoutDiagnosticOperation
    let sanitizedDocumentID: String
    let sanitizedNodeIDs: [String]
    let revision: UInt64
    let generation: UInt64
    let durationMilliseconds: Double
    let result: LayoutDiagnosticResult
    let failureCategory: LayoutFailureCategory?

    private init(
        requirementID: String,
        operation: LayoutDiagnosticOperation,
        sanitizedDocumentID: String,
        sanitizedNodeIDs: [String],
        revision: UInt64,
        generation: UInt64,
        durationMilliseconds: Double,
        result: LayoutDiagnosticResult,
        failureCategory: LayoutFailureCategory?
    ) {
        self.requirementID = requirementID
        self.operation = operation
        self.sanitizedDocumentID = sanitizedDocumentID
        self.sanitizedNodeIDs = sanitizedNodeIDs
        self.revision = revision
        self.generation = generation
        self.durationMilliseconds = durationMilliseconds
        self.result = result
        self.failureCategory = failureCategory
    }

    static func make(
        requirementID: String,
        operation: LayoutDiagnosticOperation,
        documentID: DocumentID,
        nodeIDs: [NodeID],
        revision: UInt64,
        generation: UInt64,
        durationMilliseconds: Double,
        result: LayoutDiagnosticResult,
        failureCategory: LayoutFailureCategory?
    ) -> Self {
        Self(
            requirementID: requirementID,
            operation: operation,
            sanitizedDocumentID: sanitizedIdentifier(documentID.description, namespace: "document"),
            sanitizedNodeIDs: nodeIDs.map { sanitizedIdentifier($0.description, namespace: "node") },
            revision: revision,
            generation: generation,
            durationMilliseconds: durationMilliseconds,
            result: result,
            failureCategory: failureCategory
        )
    }

    private static func sanitizedIdentifier(_ value: String, namespace: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8)).prefix(6)
            .map { String(format: "%02x", $0) }.joined()
        return "\(namespace)-\(digest)"
    }
}

actor LayoutDiagnostics {
    private var records: [LayoutDiagnosticRecord] = []
    func append(_ record: LayoutDiagnosticRecord) { records.append(record) }
    func snapshot() -> [LayoutDiagnosticRecord] { records }
}
