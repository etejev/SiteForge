import Foundation

// SF-1901-001...008; prototype-only evidence for downstream SF-0401, SF-0407, and SF-0501.

struct RunwayStableID: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) { self.rawValue = rawValue }
    var description: String { rawValue }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct RunwayPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
}

struct RunwaySize: Codable, Equatable, Sendable {
    var width: Double
    var height: Double
}

struct RunwayRect: Codable, Equatable, Sendable {
    var origin: RunwayPoint
    var size: RunwaySize

    func contains(_ point: RunwayPoint) -> Bool {
        point.x >= origin.x && point.y >= origin.y &&
            point.x <= origin.x + size.width && point.y <= origin.y + size.height
    }
}

struct RunwayViewportTransform: Equatable, Sendable {
    let zoom: Double
    let pan: RunwayPoint
    let backingScale: Double

    init(zoom: Double, pan: RunwayPoint, backingScale: Double) throws {
        guard zoom.isFinite, zoom > 0, pan.x.isFinite, pan.y.isFinite,
              backingScale.isFinite, backingScale > 0 else {
            throw RunwayError.invalidViewport
        }
        self.zoom = zoom
        self.pan = pan
        self.backingScale = backingScale
    }

    func worldToView(_ point: RunwayPoint) -> RunwayPoint {
        RunwayPoint(x: point.x * zoom + pan.x, y: point.y * zoom + pan.y)
    }

    func viewToWorld(_ point: RunwayPoint) -> RunwayPoint {
        RunwayPoint(x: (point.x - pan.x) / zoom, y: (point.y - pan.y) / zoom)
    }

    func viewToDevice(_ point: RunwayPoint) -> RunwayPoint {
        RunwayPoint(x: point.x * backingScale, y: point.y * backingScale)
    }

    func deviceToView(_ point: RunwayPoint) -> RunwayPoint {
        RunwayPoint(x: point.x / backingScale, y: point.y / backingScale)
    }

    func zoomed(to newZoom: Double, around cursor: RunwayPoint) throws -> Self {
        let anchoredWorld = viewToWorld(cursor)
        return try Self(
            zoom: newZoom,
            pan: RunwayPoint(
                x: cursor.x - anchoredWorld.x * newZoom,
                y: cursor.y - anchoredWorld.y * newZoom
            ),
            backingScale: backingScale
        )
    }

    func panned(by delta: RunwayPoint) throws -> Self {
        try Self(
            zoom: zoom,
            pan: RunwayPoint(x: pan.x + delta.x, y: pan.y + delta.y),
            backingScale: backingScale
        )
    }
}

struct RunwayCanvasObject: Equatable, Sendable {
    let id: RunwayStableID
    var bounds: RunwayRect
    let colorSeed: UInt32
}

struct RunwayOverlay: Equatable, Sendable {
    let target: RunwayStableID
    let bounds: RunwayRect
}

enum RunwayFixtures {
    static func canvasObjects(count: Int) -> [RunwayCanvasObject] {
        precondition(count >= 0)
        let columns = max(1, Int(Double(max(count, 1)).squareRoot().rounded(.up)))
        return (0..<count).map { index in
            let column = index % columns
            let row = index / columns
            return RunwayCanvasObject(
                id: RunwayStableID(String(format: "object-%05d", index)),
                bounds: RunwayRect(
                    origin: RunwayPoint(x: Double(column * 13), y: Double(row * 11)),
                    size: RunwaySize(width: 10, height: 8)
                ),
                colorSeed: UInt32(truncatingIfNeeded: index &* 2_654_435_761)
            )
        }
    }

    static func largeLayout(nodeCount: Int) -> RunwayLayoutNode {
        precondition(nodeCount > 0)
        let children = (1..<nodeCount).map { index in
            RunwayLayoutNode(
                id: RunwayStableID(String(format: "layout-%05d", index)),
                width: .fill,
                height: index.isMultiple(of: 7) ? .fixed(24) : .intrinsic,
                intrinsic: RunwaySize(width: Double(40 + index % 80), height: 18),
                constraints: RunwayConstraints(minWidth: 8, maxWidth: 2_000, minHeight: 8, maxHeight: 64)
            )
        }
        return RunwayLayoutNode(
            id: RunwayStableID("layout-root"),
            axis: .vertical,
            width: .fill,
            height: .fill,
            padding: RunwayInsets(all: 12),
            gap: 3,
            alignment: .stretch,
            overflow: .clip,
            children: children
        )
    }

    static func parityLayout() -> RunwayLayoutNode {
        let nested = RunwayLayoutNode(
            id: RunwayStableID("nested"),
            axis: .vertical,
            width: .fill,
            height: .fixed(120),
            constraints: RunwayConstraints(minWidth: 120, maxWidth: 480, minHeight: 80, maxHeight: 140),
            padding: RunwayInsets(top: 8, leading: 10, bottom: 8, trailing: 10),
            gap: 6,
            alignment: .center,
            overflow: .clip,
            children: [
                RunwayLayoutNode(id: RunwayStableID("nested-fixed"), width: .fixed(80), height: .fixed(24)),
                RunwayLayoutNode(
                    id: RunwayStableID("nested-intrinsic"), width: .intrinsic, height: .intrinsic,
                    intrinsic: RunwaySize(width: 96, height: 31)
                ),
            ]
        )
        return RunwayLayoutNode(
            id: RunwayStableID("root"),
            axis: .horizontal,
            width: .fill,
            height: .fill,
            padding: RunwayInsets(top: 16, leading: 20, bottom: 16, trailing: 20),
            gap: 12,
            alignment: .center,
            overflow: .visible,
            children: [
                RunwayLayoutNode(id: RunwayStableID("fixed"), width: .fixed(140), height: .fixed(72)),
                nested,
                RunwayLayoutNode(
                    id: RunwayStableID("intrinsic"), width: .intrinsic, height: .intrinsic,
                    intrinsic: RunwaySize(width: 110, height: 48),
                    constraints: RunwayConstraints(minWidth: 90, maxWidth: 130, minHeight: 32, maxHeight: 60)
                ),
            ]
        )
    }
}

struct RunwayHitIndex: Sendable {
    private let cellSize: Double
    private let objects: [RunwayCanvasObject]
    private let cells: [Cell: [Int]]

    private struct Cell: Hashable, Sendable {
        let x: Int
        let y: Int
    }

    init(objects: [RunwayCanvasObject], cellSize: Double = 32) {
        self.cellSize = cellSize
        self.objects = objects
        var result: [Cell: [Int]] = [:]
        for (index, object) in objects.enumerated() {
            let minX = Int(floor(object.bounds.origin.x / cellSize))
            let maxX = Int(floor((object.bounds.origin.x + object.bounds.size.width) / cellSize))
            let minY = Int(floor(object.bounds.origin.y / cellSize))
            let maxY = Int(floor((object.bounds.origin.y + object.bounds.size.height) / cellSize))
            for x in minX...maxX {
                for y in minY...maxY { result[Cell(x: x, y: y), default: []].append(index) }
            }
        }
        cells = result
    }

    func hitTest(_ point: RunwayPoint) -> RunwayStableID? {
        let cell = Cell(x: Int(floor(point.x / cellSize)), y: Int(floor(point.y / cellSize)))
        return cells[cell]?.reversed().lazy
            .map { objects[$0] }
            .first(where: { $0.bounds.contains(point) })?.id
    }
}

enum RunwayAxis: String, Codable, Sendable { case horizontal, vertical }
enum RunwayAlignment: String, Codable, Sendable { case start, center, end, stretch }
enum RunwayOverflow: String, Codable, Sendable { case visible, clip }

enum RunwayLength: Equatable, Sendable {
    case fixed(Double)
    case intrinsic
    case fill
}

struct RunwayInsets: Equatable, Sendable {
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

    init(all: Double) { self.init(top: all, leading: all, bottom: all, trailing: all) }
    static let zero = RunwayInsets(all: 0)
}

struct RunwayConstraints: Equatable, Sendable {
    var minWidth: Double = 0
    var maxWidth: Double = .greatestFiniteMagnitude
    var minHeight: Double = 0
    var maxHeight: Double = .greatestFiniteMagnitude

    func validate() throws {
        guard minWidth.isFinite, minHeight.isFinite, minWidth >= 0, minHeight >= 0,
              maxWidth >= minWidth, maxHeight >= minHeight,
              !maxWidth.isNaN, !maxHeight.isNaN else { throw RunwayError.invalidConstraints }
    }
}

struct RunwayLayoutNode: Sendable {
    let id: RunwayStableID
    var axis: RunwayAxis?
    var width: RunwayLength
    var height: RunwayLength
    var intrinsic: RunwaySize
    var constraints: RunwayConstraints
    var padding: RunwayInsets
    var gap: Double
    var alignment: RunwayAlignment
    var overflow: RunwayOverflow
    var children: [RunwayLayoutNode]

    init(
        id: RunwayStableID,
        axis: RunwayAxis? = nil,
        width: RunwayLength = .intrinsic,
        height: RunwayLength = .intrinsic,
        intrinsic: RunwaySize = RunwaySize(width: 0, height: 0),
        constraints: RunwayConstraints = RunwayConstraints(),
        padding: RunwayInsets = .zero,
        gap: Double = 0,
        alignment: RunwayAlignment = .start,
        overflow: RunwayOverflow = .visible,
        children: [RunwayLayoutNode] = []
    ) {
        self.id = id
        self.axis = axis
        self.width = width
        self.height = height
        self.intrinsic = intrinsic
        self.constraints = constraints
        self.padding = padding
        self.gap = gap
        self.alignment = alignment
        self.overflow = overflow
        self.children = children
    }
}

struct RunwayLayoutResult: Equatable, Sendable {
    let revision: Int
    let frames: [RunwayStableID: RunwayRect]
    let clipped: Set<RunwayStableID>

    func deterministicDigest() -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for id in frames.keys.sorted() {
            guard let frame = frames[id] else { continue }
            let text = "\(id.rawValue):\(frame.origin.x):\(frame.origin.y):\(frame.size.width):\(frame.size.height);"
            for byte in text.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
        }
        return String(format: "%016llx", hash)
    }
}

struct RunwayLayoutEngine: Sendable {
    func layout(
        root: RunwayLayoutNode,
        viewport: RunwaySize,
        revision: Int,
        cancellation: @Sendable (Int) -> Bool = { _ in false }
    ) throws -> RunwayLayoutResult {
        guard viewport.width.isFinite, viewport.height.isFinite,
              viewport.width > 0, viewport.height > 0 else { throw RunwayError.invalidConstraints }
        var frames: [RunwayStableID: RunwayRect] = [:]
        var clipped: Set<RunwayStableID> = []
        var visited = 0
        try place(
            root,
            frame: RunwayRect(origin: RunwayPoint(x: 0, y: 0), size: viewport),
            frames: &frames,
            clipped: &clipped,
            visited: &visited,
            cancellation: cancellation
        )
        return RunwayLayoutResult(revision: revision, frames: frames, clipped: clipped)
    }

    private func place(
        _ node: RunwayLayoutNode,
        frame: RunwayRect,
        frames: inout [RunwayStableID: RunwayRect],
        clipped: inout Set<RunwayStableID>,
        visited: inout Int,
        cancellation: @Sendable (Int) -> Bool
    ) throws {
        try node.constraints.validate()
        guard node.axis != nil || node.children.isEmpty else { throw RunwayError.unsupportedLayout }
        guard node.gap.isFinite, node.gap >= 0,
              [node.padding.top, node.padding.leading, node.padding.bottom, node.padding.trailing]
                .allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw RunwayError.invalidConstraints }
        visited += 1
        if visited.isMultiple(of: 64), cancellation(visited) { throw RunwayError.cancelled }
        let ownFrame = RunwayRect(
            origin: frame.origin,
            size: RunwaySize(
                width: clamp(frame.size.width, min: node.constraints.minWidth, max: node.constraints.maxWidth),
                height: clamp(frame.size.height, min: node.constraints.minHeight, max: node.constraints.maxHeight)
            )
        )
        frames[node.id] = ownFrame
        guard let axis = node.axis, !node.children.isEmpty else { return }

        let availableWidth = max(0, ownFrame.size.width - node.padding.leading - node.padding.trailing)
        let availableHeight = max(0, ownFrame.size.height - node.padding.top - node.padding.bottom)
        let availableMain = axis == .horizontal ? availableWidth : availableHeight
        let availableCross = axis == .horizontal ? availableHeight : availableWidth
        let gaps = node.gap * Double(max(0, node.children.count - 1))
        var fixedMain = 0.0
        var fillCount = 0
        for child in node.children {
            let rule = axis == .horizontal ? child.width : child.height
            switch rule {
            case .fill: fillCount += 1
            default: fixedMain += resolved(rule, intrinsic: axis == .horizontal ? child.intrinsic.width : child.intrinsic.height)
            }
        }
        let fillMain = fillCount == 0 ? 0 : max(0, availableMain - gaps - fixedMain) / Double(fillCount)
        var cursor = axis == .horizontal ? ownFrame.origin.x + node.padding.leading : ownFrame.origin.y + node.padding.top

        for child in node.children {
            try child.constraints.validate()
            let mainRule = axis == .horizontal ? child.width : child.height
            let crossRule = axis == .horizontal ? child.height : child.width
            let intrinsicMain = axis == .horizontal ? child.intrinsic.width : child.intrinsic.height
            let intrinsicCross = axis == .horizontal ? child.intrinsic.height : child.intrinsic.width
            var main = mainRule == .fill ? fillMain : resolved(mainRule, intrinsic: intrinsicMain)
            var cross = resolved(crossRule, intrinsic: intrinsicCross, fill: availableCross)
            if node.alignment == .stretch { cross = availableCross }
            if axis == .horizontal {
                main = clamp(main, min: child.constraints.minWidth, max: child.constraints.maxWidth)
                cross = clamp(cross, min: child.constraints.minHeight, max: child.constraints.maxHeight)
            } else {
                main = clamp(main, min: child.constraints.minHeight, max: child.constraints.maxHeight)
                cross = clamp(cross, min: child.constraints.minWidth, max: child.constraints.maxWidth)
            }
            let crossOffset: Double
            switch node.alignment {
            case .start, .stretch: crossOffset = 0
            case .center: crossOffset = (availableCross - cross) / 2
            case .end: crossOffset = availableCross - cross
            }
            let childFrame: RunwayRect
            if axis == .horizontal {
                childFrame = RunwayRect(
                    origin: RunwayPoint(x: cursor, y: ownFrame.origin.y + node.padding.top + crossOffset),
                    size: RunwaySize(width: main, height: cross)
                )
            } else {
                childFrame = RunwayRect(
                    origin: RunwayPoint(x: ownFrame.origin.x + node.padding.leading + crossOffset, y: cursor),
                    size: RunwaySize(width: cross, height: main)
                )
            }
            if node.overflow == .clip && !contains(ownFrame, childFrame) { clipped.insert(child.id) }
            try place(
                child, frame: childFrame, frames: &frames, clipped: &clipped,
                visited: &visited, cancellation: cancellation
            )
            cursor += main + node.gap
        }
    }

    private func resolved(_ length: RunwayLength, intrinsic: Double, fill: Double = 0) -> Double {
        switch length {
        case .fixed(let value): value
        case .intrinsic: intrinsic
        case .fill: fill
        }
    }

    private func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
        Swift.max(minimum, Swift.min(maximum, value))
    }

    private func contains(_ outer: RunwayRect, _ inner: RunwayRect) -> Bool {
        inner.origin.x >= outer.origin.x && inner.origin.y >= outer.origin.y &&
            inner.origin.x + inner.size.width <= outer.origin.x + outer.size.width &&
            inner.origin.y + inner.size.height <= outer.origin.y + outer.size.height
    }
}

struct RunwayVersionedResult<Value: Sendable>: Sendable {
    let revision: Int
    let value: Value

    func value(ifCurrent currentRevision: Int) -> Value? {
        revision == currentRevision ? value : nil
    }
}

enum RunwayError: Error, Equatable {
    case invalidViewport
    case invalidConstraints
    case cancelled
    case unsupportedLayout
    case oracleFailure
}
