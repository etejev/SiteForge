import CryptoKit
import Foundation

// SF-0405-001...008 — bounded transactional frame/plain-text insertion foundation.

enum InsertionKind: String, Codable, CaseIterable, Sendable {
    case frame
    case text
    case section
    case stack
    case grid

    var nodeKind: NodeKind {
        switch self {
        case .frame: .frame
        case .text: .text
        case .section: .section
        case .stack: .stack
        case .grid: .grid
        }
    }

    var requirementID: String {
        switch self {
        case .frame, .text: "SF-0405-008"
        case .section: "SF-0405-001"
        case .stack: "SF-0502-001"
        case .grid: "SF-0503-001"
        }
    }
}

enum InsertionProvenance: String, CaseIterable, Sendable {
    case pointer
    case keyboard
    case menu
    case toolbar
    case contextualMenu
    case accessibility
    case automation
}

struct InsertionGeometry: Codable, Equatable, Sendable {
    let origin: WorldPoint
    let size: WorldSize

    var frame: WorldRect { WorldRect(origin: origin, size: size) }

    static func defaultValue(for kind: InsertionKind, at point: WorldPoint) -> Self {
        let size = switch kind {
        case .frame: WorldSize(width: 240, height: 160)
        case .text: WorldSize(width: 120, height: 24)
        case .section: WorldSize(width: 960, height: 320)
        case .stack, .grid: WorldSize(width: 240, height: 160)
        }
        return Self(origin: point, size: size)
    }
}

struct InsertionOperationIdentity: Equatable, Sendable {
    let documentID: DocumentID
    let pageID: PageID
    let revision: UInt64
    let generation: UInt64
}

struct FrameInsertionCommand: Equatable, Sendable {
    let identity: InsertionOperationIdentity
    let nodeID: NodeID
    let parentID: NodeID
    let index: Int
    let geometry: InsertionGeometry
    let provenance: InsertionProvenance
}

struct TextInsertionCommand: Equatable, Sendable {
    let identity: InsertionOperationIdentity
    let nodeID: NodeID
    let parentID: NodeID
    let index: Int
    let geometry: InsertionGeometry
    let text: String
    let provenance: InsertionProvenance
}

struct ContainerInsertionCommand: Equatable, Sendable {
    let kind: InsertionKind
    let identity: InsertionOperationIdentity
    let nodeID: NodeID
    let parentID: NodeID
    let index: Int
    let geometry: InsertionGeometry
    let provenance: InsertionProvenance
}

enum AuthoringInsertionCommand: Equatable, Sendable {
    case frame(FrameInsertionCommand)
    case text(TextInsertionCommand)
    case container(ContainerInsertionCommand)

    var kind: InsertionKind {
        switch self {
        case .frame: .frame
        case .text: .text
        case .container(let value): value.kind
        }
    }

    var identity: InsertionOperationIdentity {
        switch self {
        case .frame(let value): value.identity
        case .text(let value): value.identity
        case .container(let value): value.identity
        }
    }

    var nodeID: NodeID {
        switch self {
        case .frame(let value): value.nodeID
        case .text(let value): value.nodeID
        case .container(let value): value.nodeID
        }
    }

    var parentID: NodeID {
        switch self {
        case .frame(let value): value.parentID
        case .text(let value): value.parentID
        case .container(let value): value.parentID
        }
    }

    var index: Int {
        switch self {
        case .frame(let value): value.index
        case .text(let value): value.index
        case .container(let value): value.index
        }
    }

    var geometry: InsertionGeometry {
        switch self {
        case .frame(let value): value.geometry
        case .text(let value): value.geometry
        case .container(let value): value.geometry
        }
    }

    var provenance: InsertionProvenance {
        switch self {
        case .frame(let value): value.provenance
        case .text(let value): value.provenance
        case .container(let value): value.provenance
        }
    }

    var text: String? {
        guard case .text(let value) = self else { return nil }
        return value.text
    }
}

struct InsertionValidationContext: Sendable {
    let activePageID: PageID
    let activeRoute: PageRoute
    let operationGeneration: UInt64
    let availableNodeIDs: Set<NodeID>?
    let isLifecycleAvailable: Bool
    let lifecycleDisabledReason: String?

    init(
        activePageID: PageID,
        activeRoute: PageRoute,
        operationGeneration: UInt64,
        availableNodeIDs: Set<NodeID>? = nil,
        isLifecycleAvailable: Bool = true,
        lifecycleDisabledReason: String? = nil
    ) {
        self.activePageID = activePageID
        self.activeRoute = activeRoute
        self.operationGeneration = operationGeneration
        self.availableNodeIDs = availableNodeIDs
        self.isLifecycleAvailable = isLifecycleAvailable
        self.lifecycleDisabledReason = lifecycleDisabledReason
    }
}

enum InsertionError: Error, Equatable, LocalizedError, Sendable {
    case lifecycleUnavailable(String)
    case staleDocument
    case staleRevision
    case staleGeneration
    case pageUnavailable
    case routeMismatch
    case missingParent
    case crossPageParent
    case incompatibleParent
    case lockedParent
    case hiddenParent
    case unavailableParent
    case duplicateNode
    case invalidIndex
    case invalidGeometry
    case nodeLimitExceeded
    case depthLimitExceeded
    case textLimitExceeded
    case invalidText
    case cancelled

    var errorDescription: String? {
        switch self {
        case .lifecycleUnavailable(let reason): reason
        case .staleDocument: "A different document now owns this insertion."
        case .staleRevision: "The document changed before insertion could commit."
        case .staleGeneration: "A newer insertion operation replaced this one."
        case .pageUnavailable: "The active page is no longer available."
        case .routeMismatch: "The insertion route no longer matches the active page."
        case .missingParent: "The insertion parent no longer exists."
        case .crossPageParent: "The insertion parent belongs to another page."
        case .incompatibleParent: "Only a frame on the active page can contain this object."
        case .lockedParent: "The destination frame is locked. Unlock it before inserting."
        case .hiddenParent: "The destination frame is hidden. Show it before inserting."
        case .unavailableParent: "The destination frame is not available in the current scene."
        case .duplicateNode: "A node with this stable identity already exists."
        case .invalidIndex: "The insertion position is no longer valid."
        case .invalidGeometry: "Insertion geometry must be finite, positive, and within the supported layout range."
        case .nodeLimitExceeded: "The project has reached the bounded authored-node limit."
        case .depthLimitExceeded: "The destination exceeds the bounded nesting depth."
        case .textLimitExceeded: "Plain text exceeds the bounded UTF-8 size limit."
        case .invalidText: "Plain text contains unsupported control input."
        case .cancelled: "Insertion was cancelled; the committed document is unchanged."
        }
    }
}

struct InsertionAvailability: Equatable, Sendable {
    let isEnabled: Bool
    let disabledReason: String?
    static let enabled = Self(isEnabled: true, disabledReason: nil)
    static func disabled(_ reason: String) -> Self { Self(isEnabled: false, disabledReason: reason) }
}

struct InsertionCancellation: Sendable {
    let isCancelled: @Sendable () -> Bool
    static let never = Self(isCancelled: { false })
}

struct PreparedInsertion: Equatable, Sendable {
    let kind: InsertionKind
    let node: DocumentNode
    let documentCommand: DocumentCommand
    let geometry: InsertionGeometry
}

enum InsertionPolicy {
    static let maximumNodeCount = 20_000
    static let maximumDepth = 256
    static let maximumTextBytes = 64 * 1_024
    static let defaultText = "Text"
}

struct InsertionCommandRegistry: Sendable {
    static let requirementIDs: Set<String> = [
        "SF-0405-001", "SF-0405-002", "SF-0405-003", "SF-0405-004",
        "SF-0405-005", "SF-0405-006", "SF-0405-007", "SF-0405-008",
    ]

    func availability(
        for command: AuthoringInsertionCommand,
        in document: CanonicalDocument,
        context: InsertionValidationContext
    ) -> InsertionAvailability {
        do {
            _ = try prepare(command, in: document, context: context)
            return .enabled
        } catch {
            return .disabled(error.localizedDescription)
        }
    }

    func prepare(
        _ command: AuthoringInsertionCommand,
        in document: CanonicalDocument,
        context: InsertionValidationContext,
        cancellation: InsertionCancellation = .never
    ) throws -> PreparedInsertion {
        guard !cancellation.isCancelled() else { throw InsertionError.cancelled }
        guard context.isLifecycleAvailable else {
            throw InsertionError.lifecycleUnavailable(
                context.lifecycleDisabledReason ?? "Insertion is unavailable during the current document operation."
            )
        }
        let identity = command.identity
        guard identity.documentID == document.id else { throw InsertionError.staleDocument }
        guard identity.revision == document.revision else { throw InsertionError.staleRevision }
        guard identity.generation == context.operationGeneration else { throw InsertionError.staleGeneration }
        guard identity.pageID == context.activePageID,
              let page = document.pages.first(where: { $0.id == identity.pageID }) else {
            throw InsertionError.pageUnavailable
        }
        guard page.route == context.activeRoute else { throw InsertionError.routeMismatch }
        guard !document.pages.flatMap(\.nodes).contains(where: { $0.id == command.nodeID }) else {
            throw InsertionError.duplicateNode
        }
        guard document.pages.reduce(0, { $0 + $1.nodes.count }) < InsertionPolicy.maximumNodeCount else {
            throw InsertionError.nodeLimitExceeded
        }
        guard let parent = page.nodes.first(where: { $0.id == command.parentID }) else {
            if document.pages.flatMap(\.nodes).contains(where: { $0.id == command.parentID }) {
                throw InsertionError.crossPageParent
            }
            throw InsertionError.missingParent
        }
        guard parent.kind.acceptsAuthoredChildren else { throw InsertionError.incompatibleParent }
        guard !parent.insertionBooleanProperty("locked") else { throw InsertionError.lockedParent }
        guard !parent.insertionBooleanProperty("hidden") else { throw InsertionError.hiddenParent }
        if let availableNodeIDs = context.availableNodeIDs,
           !availableNodeIDs.contains(parent.id) {
            throw InsertionError.unavailableParent
        }
        guard (0...parent.childIDs.count).contains(command.index) else {
            throw InsertionError.invalidIndex
        }
        try validate(command.geometry)
        guard try depth(of: parent.id, in: page) < InsertionPolicy.maximumDepth else {
            throw InsertionError.depthLimitExceeded
        }
        if let text = command.text {
            guard text.utf8.count <= InsertionPolicy.maximumTextBytes else {
                throw InsertionError.textLimitExceeded
            }
            guard !text.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t"
            }) else { throw InsertionError.invalidText }
        }
        guard !cancellation.isCancelled() else { throw InsertionError.cancelled }
        let node = makeNode(for: command)
        let documentCommand = DocumentCommand.insertNode(
            InsertNodeCommand(pageID: page.id, node: node, index: command.index)
        )
        guard CommandRegistry().availability(for: documentCommand, in: document).isEnabled else {
            throw InsertionError.incompatibleParent
        }
        return PreparedInsertion(
            kind: command.kind,
            node: node,
            documentCommand: documentCommand,
            geometry: command.geometry
        )
    }

    private func validate(_ geometry: InsertionGeometry) throws {
        let values = [
            geometry.origin.x, geometry.origin.y,
            geometry.size.width, geometry.size.height,
        ]
        guard values.allSatisfy(\.isFinite),
              abs(geometry.origin.x) <= LayoutPolicy.maximumDimension,
              abs(geometry.origin.y) <= LayoutPolicy.maximumDimension,
              geometry.size.width > 0,
              geometry.size.height > 0,
              geometry.size.width <= LayoutPolicy.maximumDimension,
              geometry.size.height <= LayoutPolicy.maximumDimension else {
            throw InsertionError.invalidGeometry
        }
    }

    private func depth(of nodeID: NodeID, in page: DocumentPage) throws -> Int {
        let nodes = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        var current = nodeID
        var visited = Set<NodeID>()
        var result = 0
        while let node = nodes[current] {
            guard visited.insert(current).inserted else { throw InsertionError.incompatibleParent }
            result += 1
            switch node.parent {
            case .page: return result
            case .node(let parent): current = parent
            }
        }
        throw InsertionError.missingParent
    }

    private func makeNode(for command: AuthoringInsertionCommand) -> DocumentNode {
        let placementOrigin: PropertyOrigin = command.provenance == .pointer ? .authored : .defaulted
        var properties = [
            property(command.nodeID, "layout.x", .number(command.geometry.origin.x), placementOrigin),
            property(command.nodeID, "layout.y", .number(command.geometry.origin.y), placementOrigin),
            property(command.nodeID, "layout.width", .number(command.geometry.size.width), .defaulted),
            property(command.nodeID, "layout.height", .number(command.geometry.size.height), .defaulted),
            // A blank frame must still be legible as a structural container.
            // These deterministic canonical defaults are authored appearance;
            // the selection outline and contextual measurement label remain
            // editor-only overlays.
            property(command.nodeID, "style.fill", .string(command.kind == .text ? "text-placeholder" : "surface"), .defaulted),
            property(command.nodeID, "style.border", .string(command.kind == .text ? "none" : "subtle"), .defaulted),
        ]
        switch command.kind {
        case .section:
            properties += [
                property(command.nodeID, "layout.container.kind", .string("section"), .defaulted),
                property(command.nodeID, "layout.padding", .number(48), .defaulted),
                property(command.nodeID, "layout.axis", .string("vertical"), .defaulted),
            ]
        case .stack:
            properties += [
                property(command.nodeID, "layout.container.kind", .string("stack"), .defaulted),
                property(command.nodeID, "layout.axis", .string("vertical"), .defaulted),
                property(command.nodeID, "layout.padding", .number(24), .defaulted),
                property(command.nodeID, "layout.gap", .number(24), .defaulted),
                property(command.nodeID, "layout.align", .string("start"), .defaulted),
            ]
        case .grid:
            properties += [
                property(command.nodeID, "layout.container.kind", .string("grid"), .defaulted),
                property(command.nodeID, "layout.padding", .number(24), .defaulted),
                property(command.nodeID, "layout.gap", .number(24), .defaulted),
                property(command.nodeID, "layout.grid.columns", .number(2), .defaulted),
                property(command.nodeID, "layout.grid.placement", .string("row-major"), .defaulted),
            ]
        case .frame, .text: break
        }
        if let text = command.text {
            properties.append(property(command.nodeID, "content.text", .string(text), .defaulted))
        }
        return DocumentNode(
            id: command.nodeID,
            kind: command.kind.nodeKind,
            name: command.kind.rawValue.capitalized,
            parent: .node(command.parentID),
            properties: properties
        )
    }

    private func property(
        _ nodeID: NodeID,
        _ key: String,
        _ value: PropertyValue,
        _ origin: PropertyOrigin
    ) -> NodeProperty {
        NodeProperty(
            id: PropertyID(Self.derivedUUID(namespace: nodeID.rawValue, label: key)),
            key: PropertyKey(rawValue: key),
            value: value,
            origin: origin
        )
    }

    private static func derivedUUID(namespace: UUID, label: String) -> UUID {
        var data = Data(namespace.uuidString.lowercased().utf8)
        data.append(Data(label.utf8))
        var bytes = Array(SHA256.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

extension DocumentNode {
    func insertionProperty(_ key: String) -> NodeProperty? {
        properties.first { $0.key.rawValue == key }
    }

    func insertionNumberProperty(_ key: String) -> Double? {
        guard let property = insertionProperty(key), case .number(let value) = property.value else {
            return nil
        }
        return value
    }

    func insertionStringProperty(_ key: String) -> String? {
        guard let property = insertionProperty(key), case .string(let value) = property.value else {
            return nil
        }
        return value
    }

    func insertionBooleanProperty(_ key: String) -> Bool {
        guard let property = insertionProperty(key), case .boolean(let value) = property.value else {
            return false
        }
        return value
    }

    var insertionGeometry: InsertionGeometry? {
        guard let x = insertionNumberProperty("layout.x"),
              let y = insertionNumberProperty("layout.y"),
              let width = insertionNumberProperty("layout.width"),
              let height = insertionNumberProperty("layout.height") else { return nil }
        return InsertionGeometry(
            origin: WorldPoint(x: x, y: y),
            size: WorldSize(width: width, height: height)
        )
    }
}

/// Resolves the bounded authored container semantics from canonical node
/// ownership and defaulted properties. World space remains top-left/Y-down;
/// this shared resolver feeds the renderer and selection scene rather than
/// storing an editor-only second geometry source.
enum GridRowOffsetResolver {
    /// Computes each row origin with one height read per child and one pass
    /// over the resulting rows. Keeping this work explicit prevents a prefix
    /// reduction per child from turning large grids into quadratic work.
    static func resolve(
        childCount: Int,
        columns: Int,
        startY: Double,
        gap: Double,
        heightAt: (Int) -> Double?
    ) -> [Double] {
        guard childCount > 0 else { return [] }
        let columns = max(1, columns)
        let rowCount = (childCount + columns - 1) / columns
        var rowHeights = Array(repeating: 0.0, count: rowCount)
        for index in 0..<childCount {
            guard let height = heightAt(index) else { continue }
            let row = index / columns
            rowHeights[row] = max(rowHeights[row], height)
        }

        var rowOffsets = Array(repeating: startY, count: rowCount)
        var cursor = startY
        for row in 0..<rowCount {
            rowOffsets[row] = cursor
            cursor += rowHeights[row] + gap
        }
        return rowOffsets
    }
}

extension DocumentPage {
    func resolvedStructuralGeometry() -> [NodeID: InsertionGeometry] {
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var result = Dictionary(uniqueKeysWithValues: nodes.compactMap { node in
            node.insertionGeometry.map { (node.id, $0) }
        })
        for parent in canonicalDepthFirstNodes() {
            guard let parentGeometry = result[parent.id] else { continue }
            let children = parent.childIDs.compactMap { nodesByID[$0] }
            switch parent.kind {
            case .stack:
                let padding = parent.insertionNumberProperty("layout.padding") ?? 24
                let gap = parent.insertionNumberProperty("layout.gap") ?? 24
                var cursor = parentGeometry.origin.y + padding
                for child in children {
                    guard var geometry = result[child.id] else { continue }
                    geometry = .init(origin: .init(x: parentGeometry.origin.x + padding, y: cursor), size: geometry.size)
                    result[child.id] = geometry
                    cursor += geometry.size.height + gap
                }
            case .grid:
                let padding = parent.insertionNumberProperty("layout.padding") ?? 24
                let gap = parent.insertionNumberProperty("layout.gap") ?? 24
                let columns = max(1, Int(parent.insertionNumberProperty("layout.grid.columns") ?? 2))
                let usableWidth = max(1, parentGeometry.size.width - (2 * padding) - (Double(columns - 1) * gap))
                let cellWidth = usableWidth / Double(columns)
                let rowOffsets = GridRowOffsetResolver.resolve(
                    childCount: children.count,
                    columns: columns,
                    startY: parentGeometry.origin.y + padding,
                    gap: gap
                ) { index in
                    result[children[index].id]?.size.height
                }
                for (index, child) in children.enumerated() {
                    guard var geometry = result[child.id] else { continue }
                    let row = index / columns
                    let column = index % columns
                    geometry = .init(
                        origin: .init(
                            x: parentGeometry.origin.x + padding + Double(column) * (cellWidth + gap),
                            y: rowOffsets[row]
                        ),
                        size: .init(width: cellWidth, height: geometry.size.height)
                    )
                    result[child.id] = geometry
                }
            case .frame, .section, .text, .image, .component: break
            }
        }
        return result
    }
}

struct InsertionPreview: Equatable, Sendable {
    let kind: InsertionKind
    let nodeID: NodeID
    let geometry: InsertionGeometry
}

enum InsertionSessionPhase: Equatable, Sendable {
    case inactive
    case armed(InsertionKind)
    case previewing(InsertionPreview)
    case committing(InsertionPreview)
    case cancelled
    case failed(InsertionError)
}

struct InsertionSession: Equatable, Sendable {
    private(set) var generation: UInt64 = 0
    private(set) var identity: InsertionOperationIdentity?
    private(set) var phase: InsertionSessionPhase = .inactive

    mutating func arm(kind: InsertionKind, documentID: DocumentID, pageID: PageID, revision: UInt64) {
        generation &+= 1
        identity = InsertionOperationIdentity(
            documentID: documentID,
            pageID: pageID,
            revision: revision,
            generation: generation
        )
        phase = .armed(kind)
    }

    mutating func preview(at point: WorldPoint, nodeID: NodeID = NodeID()) {
        let kind: InsertionKind
        switch phase {
        case .armed(let value): kind = value
        case .previewing(let value): kind = value.kind
        default: return
        }
        phase = .previewing(InsertionPreview(
            kind: kind,
            nodeID: nodeID,
            geometry: .defaultValue(for: kind, at: point)
        ))
    }

    mutating func beginCommit(_ preview: InsertionPreview) { phase = .committing(preview) }
    mutating func complete() { identity = nil; phase = .inactive }
    mutating func fail(_ error: InsertionError) { phase = .failed(error) }

    mutating func cancel() {
        generation &+= 1
        identity = nil
        phase = .cancelled
    }

    mutating func deactivate() {
        generation &+= 1
        identity = nil
        phase = .inactive
    }
}

enum InsertionLayoutAdapter {
    static func snapshot(for node: DocumentNode) -> LayoutSnapshot? {
        guard let geometry = node.insertionGeometry else { return nil }
        if node.kind == .text {
            let key = LayoutIntrinsicKey(rawValue: "text-\(node.id.description)")
            return LayoutSnapshot(
                rootID: node.id,
                nodes: [LayoutNodeSnapshot(
                    id: node.id,
                    width: .intrinsic,
                    height: .intrinsic,
                    intrinsicKey: key
                )],
                intrinsicCatalog: LayoutIntrinsicCatalog(entries: [
                    key: LayoutSize(width: geometry.size.width, height: geometry.size.height),
                ])
            )
        }
        return LayoutSnapshot(
            rootID: node.id,
            nodes: [LayoutNodeSnapshot(
                id: node.id,
                width: .fixed(geometry.size.width),
                height: .fixed(geometry.size.height)
            )]
        )
    }
}

enum InsertionDiagnosticResult: String, Codable, Sendable {
    case success, failure, cancelled, stale
}

struct InsertionDiagnosticRecord: Codable, Equatable, Sendable {
    let requirementID: String
    let commandType: String
    let sanitizedIdentifiers: [String]
    let durationMilliseconds: Double
    let parentRevision: UInt64
    let resultRevision: UInt64?
    let affectedObjectCount: Int
    let result: InsertionDiagnosticResult
    let failureCategory: String?
}

actor InsertionDiagnostics {
    private var records: [InsertionDiagnosticRecord] = []
    func append(_ record: InsertionDiagnosticRecord) { records.append(record) }
    func snapshot() -> [InsertionDiagnosticRecord] { records }
}

enum InsertionDiagnosticFactory {
    static func make(
        kind: InsertionKind,
        nodeID: NodeID,
        parentID: NodeID,
        durationMilliseconds: Double,
        parentRevision: UInt64,
        resultRevision: UInt64?,
        result: InsertionDiagnosticResult,
        failure: InsertionError? = nil
    ) -> InsertionDiagnosticRecord {
        InsertionDiagnosticRecord(
            requirementID: "SF-0405-008",
            commandType: "insert-\(kind.rawValue)",
            sanitizedIdentifiers: [nodeID, parentID].map { String($0.description.prefix(8)) },
            durationMilliseconds: max(0, durationMilliseconds),
            parentRevision: parentRevision,
            resultRevision: resultRevision,
            affectedObjectCount: result == .success ? 1 : 0,
            result: result,
            failureCategory: failure.map { category(for: $0) }
        )
    }

    private static func category(for error: InsertionError) -> String {
        switch error {
        case .cancelled: "cancelled"
        case .staleDocument, .staleRevision, .staleGeneration: "stale"
        case .lockedParent: "locked-parent"
        case .hiddenParent: "hidden-parent"
        case .unavailableParent: "unavailable-parent"
        case .missingParent, .crossPageParent, .incompatibleParent: "invalid-parent"
        case .duplicateNode: "duplicate-identity"
        case .invalidGeometry: "invalid-geometry"
        case .textLimitExceeded, .nodeLimitExceeded, .depthLimitExceeded: "resource-limit"
        default: "validation"
        }
    }
}
