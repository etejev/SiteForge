import CryptoKit
import Foundation

// SF-0408-001...008 — bounded local reorder, nesting, and placement.
// The canonical mutation is only DocumentCommand.moveNode; all session state below
// intentionally remains scene/window-owned editor convenience state.

enum DragSessionIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "drag-session"
}
typealias DragSessionID = StableIdentifier<DragSessionIdentifierDomain>

/// Opaque capability for a native drag callback. A raw node identifier alone
/// never authorizes an asynchronously delivered drop to mutate this scene.
struct LocalLayerDragTransfer: Codable, Equatable, Sendable {
    let sessionID: DragSessionID
    let sourceNodeID: NodeID
}

/// An event-order token is local editor convenience state. Native item-provider
/// callbacks may arrive after a row is exited or a newer target is entered; the
/// token prevents an older callback from reviving a preview or commit path.
struct LocalLayerDragCallbackToken: Equatable, Sendable {
    let sessionID: DragSessionID
    let generation: UInt64
}

enum DragDropProvenance: String, Codable, CaseIterable, Sendable {
    case pointer, keyboard, menu, contextualMenu, accessibility, automation
}

enum DragDestination: Equatable, Sendable {
    case root(PageID, index: Int)
    case container(NodeID, index: Int)

    var parent: NodeParent {
        switch self { case .root(let pageID, _): .page(pageID); case .container(let id, _): .node(id) }
    }
    var requestedIndex: Int { switch self { case .root(_, let index), .container(_, let index): index } }
}

struct DragOperationIdentity: Equatable, Sendable {
    let sessionID: DragSessionID
    let documentID: DocumentID
    let pageID: PageID
    let revision: UInt64
    let sceneID: CanvasViewportSceneID
    let rendererGeneration: UInt64
}

struct DragDropCommand: Equatable, Sendable {
    let identity: DragOperationIdentity
    let sourceNodeID: NodeID
    let destination: DragDestination
    let provenance: DragDropProvenance
}

struct DragDropValidationContext: Sendable {
    let activePageID: PageID
    let sceneID: CanvasViewportSceneID
    let rendererGeneration: UInt64
    let availableNodeIDs: Set<NodeID>
    let isLifecycleAvailable: Bool
    let lifecycleDisabledReason: String?
}

enum DragDropError: Error, Equatable, LocalizedError, Sendable {
    case lifecycleUnavailable(String), staleDocument, staleRevision, staleRenderer, pageUnavailable
    case missingSource, unavailableSource, lockedSource, hiddenSource, crossPageSource
    case sourceNotSelected, multipleSelectionUnsupported
    case missingDestination, unavailableDestination, lockedDestination, hiddenDestination
    case incompatibleContainer, invalidIndex, noOp, cycle, depthLimit, revisionExhausted, cancelled

    var errorDescription: String? {
        switch self {
        case .lifecycleUnavailable(let reason): reason
        case .staleDocument: "A different document now owns this drag session."
        case .staleRevision: "The document changed before this drag could commit."
        case .staleRenderer: "A newer rendered scene replaced this drag session."
        case .pageUnavailable: "The active page is no longer available."
        case .missingSource: "The dragged object no longer exists."
        case .unavailableSource: "The dragged object is unavailable in the current scene."
        case .lockedSource: "Locked objects cannot be reordered or nested."
        case .hiddenSource: "Hidden objects cannot be dragged."
        case .crossPageSource: "Objects cannot move across pages in this bounded slice."
        case .sourceNotSelected: "Select this layer before moving it."
        case .multipleSelectionUnsupported: "Move exactly one selected layer in this bounded slice."
        case .missingDestination: "The destination is no longer available."
        case .unavailableDestination: "The destination is unavailable in the current scene."
        case .lockedDestination: "The destination container is locked."
        case .hiddenDestination: "The destination container is hidden."
        case .incompatibleContainer: "Only frame containers accept nested objects."
        case .invalidIndex: "The requested insertion position is no longer valid."
        case .noOp: "This drop keeps the object in the same position."
        case .cycle: "An object cannot be nested inside itself or its descendant."
        case .depthLimit: "This move would exceed the supported nesting depth."
        case .revisionExhausted: "The document revision cannot accept another drag operation."
        case .cancelled: "The drag was cancelled; the committed document is unchanged."
        }
    }
}

struct DragDropAvailability: Equatable, Sendable {
    let isEnabled: Bool
    let disabledReason: String?
    static let enabled = Self(isEnabled: true, disabledReason: nil)
    static func disabled(_ error: DragDropError) -> Self { .init(isEnabled: false, disabledReason: error.localizedDescription) }
}

enum DragDropPolicy {
    static let maximumDepth = 32
    static let requirementIDs: Set<String> = [
        "SF-0408-001", "SF-0408-002", "SF-0408-003", "SF-0408-004",
        "SF-0408-005", "SF-0408-006", "SF-0408-007", "SF-0408-008",
    ]
}

struct DragDropPreview: Equatable, Sendable {
    let identity: DragOperationIdentity
    let sourceNodeID: NodeID
    let destination: DragDestination
    let committedDestination: DragDestination
}

enum DragSessionPhase: Equatable, Sendable {
    case inactive, drafting(DragOperationIdentity), previewing(DragDropPreview), committing(DragDropPreview), cancelled, failed(DragDropError)
}

struct DragDropSession: Equatable, Sendable {
    private(set) var phase: DragSessionPhase = .inactive
    /// Keep the active identity through a rejected hover. Native drag targets
    /// can report an invalid row before the pointer exits it and enters a valid
    /// row; rejecting that preview must not revoke the source capability.
    private(set) var activeIdentity: DragOperationIdentity?
    var identity: DragOperationIdentity? { activeIdentity }
    mutating func begin(documentID: DocumentID, pageID: PageID, revision: UInt64, sceneID: CanvasViewportSceneID, rendererGeneration: UInt64) -> DragOperationIdentity {
        let value = DragOperationIdentity(sessionID: DragSessionID(), documentID: documentID, pageID: pageID, revision: revision, sceneID: sceneID, rendererGeneration: rendererGeneration)
        activeIdentity = value; phase = .drafting(value); return value
    }
    mutating func preview(_ value: DragDropPreview) { phase = .previewing(value) }
    mutating func clearPreview() {
        switch phase {
        case .previewing(let value):
            phase = .drafting(value.identity)
        case .failed:
            guard let activeIdentity else { return }
            phase = .drafting(activeIdentity)
        default:
            return
        }
    }
    mutating func commit() -> DragDropPreview? { guard case .previewing(let value) = phase else { return nil }; phase = .committing(value); return value }
    mutating func cancel() { activeIdentity = nil; phase = .cancelled }
    mutating func fail(_ error: DragDropError) { phase = .failed(error) }
    mutating func deactivate() { activeIdentity = nil; phase = .inactive }
}

struct PreparedDragDrop: Equatable, Sendable {
    let command: DocumentCommand
    let preview: DragDropPreview
}

struct DragDropCommandRegistry: Sendable {
    static let requirementIDs = DragDropPolicy.requirementIDs

    func availability(for command: DragDropCommand, in document: CanonicalDocument, context: DragDropValidationContext) -> DragDropAvailability {
        do { _ = try prepare(command, in: document, context: context); return .enabled }
        catch let error as DragDropError { return .disabled(error) }
        catch { return .disabled(.invalidIndex) }
    }

    func prepare(_ command: DragDropCommand, in document: CanonicalDocument, context: DragDropValidationContext, cancellation: CommandCancellation = .never) throws -> PreparedDragDrop {
        guard !cancellation.isCancelled() else { throw DragDropError.cancelled }
        guard context.isLifecycleAvailable else { throw DragDropError.lifecycleUnavailable(context.lifecycleDisabledReason ?? "Dragging is unavailable right now.") }
        guard command.identity.documentID == document.id else { throw DragDropError.staleDocument }
        guard command.identity.revision == document.revision else { throw DragDropError.staleRevision }
        guard command.identity.sceneID == context.sceneID, command.identity.rendererGeneration == context.rendererGeneration else { throw DragDropError.staleRenderer }
        guard command.identity.pageID == context.activePageID, let page = document.pages.first(where: { $0.id == command.identity.pageID }) else { throw DragDropError.pageUnavailable }
        guard document.revision < UInt64.max - 1 else { throw DragDropError.revisionExhausted }
        let hierarchy = HierarchyIndex(page: page)
        guard !hierarchy.hasDuplicateNodeIDs else { throw DragDropError.invalidIndex }
        guard let source = hierarchy.nodes[command.sourceNodeID] else {
            if document.pages.flatMap(\.nodes).contains(where: { $0.id == command.sourceNodeID }) { throw DragDropError.crossPageSource }
            throw DragDropError.missingSource
        }
        guard context.availableNodeIDs.contains(source.id) else { throw DragDropError.unavailableSource }
        guard !source.dragBoolean("locked") else { throw DragDropError.lockedSource }
        guard !source.dragBoolean("hidden") else { throw DragDropError.hiddenSource }
        let destination = try resolve(command.destination, hierarchy: hierarchy, context: context)
        guard destination.parent != .node(source.id),
              !(try hierarchy.isDescendant(destination.parent, of: source.id, cancellation: cancellation)) else {
            throw DragDropError.cycle
        }
        let parentDepth = try hierarchy.depth(of: destination.parent, cancellation: cancellation)
        let movingSubtreeDepth = try hierarchy.subtreeDepth(of: source.id, cancellation: cancellation)
        guard parentDepth + movingSubtreeDepth <= DragDropPolicy.maximumDepth else {
            throw DragDropError.depthLimit
        }
        let adjusted = adjustedDestination(command.destination, source: source, hierarchy: hierarchy)
        if source.parent == adjusted.parent,
           hierarchy.index(of: source.id) == adjusted.requestedIndex {
            // Canonical move indices are pre-removal indices, but the preview
            // is post-removal. Reject a no-op at the shared preparation seam
            // so it cannot create a revision, history entry, autosave, or
            // misleading Undo availability.
            throw DragDropError.noOp
        }
        let canonical = DocumentCommand.moveNode(MoveNodeCommand(pageID: page.id, nodeID: source.id, destination: destination.parent, index: command.destination.requestedIndex))
        guard CommandRegistry().availability(for: canonical, in: document).isEnabled else { throw DragDropError.invalidIndex }
        return PreparedDragDrop(command: canonical, preview: DragDropPreview(identity: command.identity, sourceNodeID: source.id, destination: command.destination, committedDestination: adjusted))
    }

    private func resolve(_ destination: DragDestination, hierarchy: HierarchyIndex, context: DragDropValidationContext) throws -> DragDestination {
        switch destination {
        case .root(let pageID, let index):
            guard pageID == hierarchy.pageID, (0...hierarchy.rootNodeIDs.count).contains(index) else { throw DragDropError.invalidIndex }
            return destination
        case .container(let id, let index):
            guard let target = hierarchy.nodes[id] else { throw DragDropError.missingDestination }
            guard context.availableNodeIDs.contains(id) else { throw DragDropError.unavailableDestination }
            guard target.kind == .frame else { throw DragDropError.incompatibleContainer }
            guard !target.dragBoolean("locked") else { throw DragDropError.lockedDestination }
            guard !target.dragBoolean("hidden") else { throw DragDropError.hiddenDestination }
            guard (0...target.childIDs.count).contains(index) else { throw DragDropError.invalidIndex }
            return destination
        }
    }

    private func adjustedDestination(_ destination: DragDestination, source: DocumentNode, hierarchy: HierarchyIndex) -> DragDestination {
        let sameParent = source.parent == destination.parent
        let sourceIndex: Int? = switch source.parent {
        case .page: hierarchy.rootNodeIDs.firstIndex(of: source.id)
        case .node(let id): hierarchy.nodes[id]?.childIDs.firstIndex(of: source.id)
        }
        guard sameParent, let sourceIndex, sourceIndex < destination.requestedIndex else { return destination }
        switch destination {
        case .root(let id, let index): return .root(id, index: index - 1)
        case .container(let id, let index): return .container(id, index: index - 1)
        }
    }

    private struct HierarchyIndex {
        let pageID: PageID
        let rootNodeIDs: [NodeID]
        let nodes: [NodeID: DocumentNode]
        let hasDuplicateNodeIDs: Bool

        init(page: DocumentPage) {
            pageID = page.id
            rootNodeIDs = page.rootNodeIDs
            var indexed: [NodeID: DocumentNode] = [:]
            var duplicate = false
            for node in page.nodes {
                if indexed[node.id] != nil { duplicate = true }
                else { indexed[node.id] = node }
            }
            nodes = indexed
            hasDuplicateNodeIDs = duplicate
        }

        func index(of nodeID: NodeID) -> Int? {
            guard let node = nodes[nodeID] else { return nil }
            return switch node.parent {
            case .page:
                rootNodeIDs.firstIndex(of: nodeID)
            case .node(let parentID):
                nodes[parentID]?.childIDs.firstIndex(of: nodeID)
            }
        }

        func isDescendant(
            _ parent: NodeParent,
            of source: NodeID,
            cancellation: CommandCancellation
        ) throws -> Bool {
            guard case .node(let target) = parent else { return false }
            var pending = nodes[source]?.childIDs ?? []
            var visited = Set<NodeID>()
            while let value = pending.popLast() {
                if cancellation.isCancelled() { throw DragDropError.cancelled }
                if value == target { return true }
                if visited.insert(value).inserted {
                    pending.append(contentsOf: nodes[value]?.childIDs ?? [])
                }
            }
            return false
        }

        func depth(of parent: NodeParent, cancellation: CommandCancellation) throws -> Int {
            var value = 0
            var current = parent
            var visited = Set<NodeID>()
            while case .node(let id) = current, let node = nodes[id] {
                if cancellation.isCancelled() { throw DragDropError.cancelled }
                // `childIDs` are validated independently from `parent`; a
                // malformed in-memory graph can therefore contain a parent
                // cycle that is not reachable by descendant traversal. Never
                // let pre-commit validation spin on such an input.
                guard visited.insert(id).inserted else { throw DragDropError.cycle }
                value += 1
                // The caller turns this sentinel into the typed depth-limit
                // result. It bounds work even if a malformed live model has a
                // much deeper parent chain than canonical package limits.
                if value > DragDropPolicy.maximumDepth { return value }
                current = node.parent
            }
            return value
        }

        func subtreeDepth(of id: NodeID, cancellation: CommandCancellation) throws -> Int {
            guard let node = nodes[id] else { return 1 }
            var maximum = 1
            var pending: [(NodeID, Int)] = node.childIDs.map { ($0, 2) }
            var visited = Set<NodeID>()
            while let (candidate, depth) = pending.popLast() {
                if cancellation.isCancelled() { throw DragDropError.cancelled }
                guard visited.insert(candidate).inserted else { continue }
                maximum = max(maximum, depth)
                if maximum > DragDropPolicy.maximumDepth { return maximum }
                for child in nodes[candidate]?.childIDs ?? [] {
                    pending.append((child, depth + 1))
                }
            }
            return maximum
        }
    }
}

private extension DocumentNode {
    func dragBoolean(_ key: String) -> Bool { properties.first(where: { $0.key.rawValue == key }).flatMap { if case .boolean(let value) = $0.value { value } else { nil } } ?? false }
}

enum DragDropDiagnosticResult: String, Codable, Sendable { case success, failure, cancelled, stale }
struct DragDropDiagnosticRecord: Codable, Equatable, Sendable {
    let requirementIDs: [String]; let operationType: String; let provenance: DragDropProvenance; let sanitizedIdentifiers: [String]; let durationMilliseconds: Double; let result: DragDropDiagnosticResult; let failureCategory: String?
}
actor DragDropDiagnostics { private var records: [DragDropDiagnosticRecord] = []; func append(_ value: DragDropDiagnosticRecord) { records.append(value) }; func snapshot() -> [DragDropDiagnosticRecord] { records } }
enum DragDropDiagnosticFactory {
    static func make(command: DragDropCommand, durationMilliseconds: Double, result: DragDropDiagnosticResult, failure: DragDropError?) -> DragDropDiagnosticRecord {
        let digest = SHA256.hash(data: Data(("drag:" + command.sourceNodeID.description).utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        return .init(requirementIDs: DragDropPolicy.requirementIDs.sorted(), operationType: "move-node", provenance: command.provenance, sanitizedIdentifiers: ["node-" + digest], durationMilliseconds: max(0, durationMilliseconds), result: result, failureCategory: failure.map(\.diagnosticCategory))
    }
}

private extension DragDropError {
    /// Diagnostics classify a failure without serializing associated values.
    /// In particular, lifecycle-disabled reasons can originate at a UI or
    /// filesystem boundary and are not safe diagnostic payloads.
    var diagnosticCategory: String {
        switch self {
        case .lifecycleUnavailable: "lifecycle-unavailable"
        case .staleDocument: "stale-document"
        case .staleRevision: "stale-revision"
        case .staleRenderer: "stale-renderer"
        case .pageUnavailable: "page-unavailable"
        case .missingSource: "missing-source"
        case .unavailableSource: "unavailable-source"
        case .lockedSource: "locked-source"
        case .hiddenSource: "hidden-source"
        case .crossPageSource: "cross-page-source"
        case .sourceNotSelected: "source-not-selected"
        case .multipleSelectionUnsupported: "multiple-selection-unsupported"
        case .missingDestination: "missing-destination"
        case .unavailableDestination: "unavailable-destination"
        case .lockedDestination: "locked-destination"
        case .hiddenDestination: "hidden-destination"
        case .incompatibleContainer: "incompatible-container"
        case .invalidIndex: "invalid-index"
        case .noOp: "no-op"
        case .cycle: "cycle"
        case .depthLimit: "depth-limit"
        case .revisionExhausted: "revision-exhausted"
        case .cancelled: "cancelled"
        }
    }
}
