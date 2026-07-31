import CryptoKit
import Foundation

// SF-0408-001...008 — bounded local reorder, nesting, and placement.
// The canonical mutation is only DocumentCommand.moveNode; all session state below
// intentionally remains scene/window-owned editor convenience state.

enum DragSessionIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "drag-session"
}
typealias DragSessionID = StableIdentifier<DragSessionIdentifierDomain>

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
    case missingDestination, unavailableDestination, lockedDestination, hiddenDestination
    case incompatibleContainer, invalidIndex, cycle, depthLimit, revisionExhausted, cancelled

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
        case .missingDestination: "The destination is no longer available."
        case .unavailableDestination: "The destination is unavailable in the current scene."
        case .lockedDestination: "The destination container is locked."
        case .hiddenDestination: "The destination container is hidden."
        case .incompatibleContainer: "Only frame containers accept nested objects."
        case .invalidIndex: "The requested insertion position is no longer valid."
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
    var identity: DragOperationIdentity? {
        switch phase { case .drafting(let v): v; case .previewing(let v), .committing(let v): v.identity; default: nil }
    }
    mutating func begin(documentID: DocumentID, pageID: PageID, revision: UInt64, sceneID: CanvasViewportSceneID, rendererGeneration: UInt64) -> DragOperationIdentity {
        let value = DragOperationIdentity(sessionID: DragSessionID(), documentID: documentID, pageID: pageID, revision: revision, sceneID: sceneID, rendererGeneration: rendererGeneration)
        phase = .drafting(value); return value
    }
    mutating func preview(_ value: DragDropPreview) { phase = .previewing(value) }
    mutating func commit() -> DragDropPreview? { guard case .previewing(let value) = phase else { return nil }; phase = .committing(value); return value }
    mutating func cancel() { phase = .cancelled }
    mutating func fail(_ error: DragDropError) { phase = .failed(error) }
    mutating func deactivate() { phase = .inactive }
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
        guard let source = page.nodes.first(where: { $0.id == command.sourceNodeID }) else {
            if document.pages.flatMap(\.nodes).contains(where: { $0.id == command.sourceNodeID }) { throw DragDropError.crossPageSource }
            throw DragDropError.missingSource
        }
        guard context.availableNodeIDs.contains(source.id) else { throw DragDropError.unavailableSource }
        guard !source.dragBoolean("locked") else { throw DragDropError.lockedSource }
        guard !source.dragBoolean("hidden") else { throw DragDropError.hiddenSource }
        let destination = try resolve(command.destination, source: source, page: page, context: context)
        guard destination.parent != .node(source.id), !isDescendant(destination.parent, of: source.id, in: page) else { throw DragDropError.cycle }
        guard depth(of: destination.parent, in: page) + subtreeDepth(of: source.id, in: page) <= DragDropPolicy.maximumDepth else { throw DragDropError.depthLimit }
        let canonical = DocumentCommand.moveNode(MoveNodeCommand(pageID: page.id, nodeID: source.id, destination: destination.parent, index: command.destination.requestedIndex))
        guard CommandRegistry().availability(for: canonical, in: document).isEnabled else { throw DragDropError.invalidIndex }
        let adjusted = adjustedDestination(command.destination, source: source, page: page)
        return PreparedDragDrop(command: canonical, preview: DragDropPreview(identity: command.identity, sourceNodeID: source.id, destination: command.destination, committedDestination: adjusted))
    }

    private func resolve(_ destination: DragDestination, source: DocumentNode, page: DocumentPage, context: DragDropValidationContext) throws -> DragDestination {
        switch destination {
        case .root(let pageID, let index):
            guard pageID == page.id, (0...page.rootNodeIDs.count).contains(index) else { throw DragDropError.invalidIndex }
            return destination
        case .container(let id, let index):
            guard let target = page.nodes.first(where: { $0.id == id }) else { throw DragDropError.missingDestination }
            guard context.availableNodeIDs.contains(id) else { throw DragDropError.unavailableDestination }
            guard target.kind == .frame else { throw DragDropError.incompatibleContainer }
            guard !target.dragBoolean("locked") else { throw DragDropError.lockedDestination }
            guard !target.dragBoolean("hidden") else { throw DragDropError.hiddenDestination }
            guard (0...target.childIDs.count).contains(index) else { throw DragDropError.invalidIndex }
            return destination
        }
    }

    private func adjustedDestination(_ destination: DragDestination, source: DocumentNode, page: DocumentPage) -> DragDestination {
        let sameParent = source.parent == destination.parent
        let sourceIndex: Int? = switch source.parent {
        case .page: page.rootNodeIDs.firstIndex(of: source.id)
        case .node(let id): page.nodes.first(where: { $0.id == id })?.childIDs.firstIndex(of: source.id)
        }
        guard sameParent, let sourceIndex, sourceIndex < destination.requestedIndex else { return destination }
        switch destination {
        case .root(let id, let index): return .root(id, index: index - 1)
        case .container(let id, let index): return .container(id, index: index - 1)
        }
    }

    private func isDescendant(_ parent: NodeParent, of source: NodeID, in page: DocumentPage) -> Bool {
        guard case .node(let target) = parent else { return false }
        var pending = page.nodes.first(where: { $0.id == source })?.childIDs ?? []
        var visited = Set<NodeID>()
        while let value = pending.popLast() { if value == target { return true }; if visited.insert(value).inserted { pending.append(contentsOf: page.nodes.first(where: { $0.id == value })?.childIDs ?? []) } }
        return false
    }
    private func depth(of parent: NodeParent, in page: DocumentPage) -> Int {
        var value = 0; var current = parent
        while case .node(let id) = current, let node = page.nodes.first(where: { $0.id == id }) { value += 1; current = node.parent }
        return value
    }
    private func subtreeDepth(of id: NodeID, in page: DocumentPage) -> Int {
        guard let node = page.nodes.first(where: { $0.id == id }) else { return 1 }
        return 1 + (node.childIDs.map { subtreeDepth(of: $0, in: page) }.max() ?? 0)
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
        return .init(requirementIDs: DragDropPolicy.requirementIDs.sorted(), operationType: "move-node", provenance: command.provenance, sanitizedIdentifiers: ["node-" + digest], durationMilliseconds: max(0, durationMilliseconds), result: result, failureCategory: failure.map { String(describing: $0).prefix(64).description })
    }
}
