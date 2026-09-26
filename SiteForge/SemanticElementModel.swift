import Foundation

// SF-1203-001...008 — one typed, identity-gated semantic element command.
// The Inspector only supplies a selection; this registry owns validation and
// property mutation so semantic metadata cannot become a view-local truth.
enum SemanticElementInspectorValue: Equatable, Sendable {
    case unavailable(String)
    case single(SemanticHTMLElement, PropertyOrigin)
    case mixed(applicableCount: Int, skippedCount: Int)
}

enum SemanticElementEdit: Sendable {
    case set(SemanticHTMLElement)
    case reset
}

struct SemanticElementCommand: Sendable {
    let identity: DesignInspectorOperationIdentity
    let orderedNodeIDs: [NodeID]
    let edit: SemanticElementEdit
    let provenance: DesignInspectorProvenance
    let cancelled: Bool
}

enum SemanticElementCommandError: Error, LocalizedError, Equatable, Sendable {
    case stale, cancelled, invalidElement, unavailable(String), noApplicableTargets, noChanges
    var errorDescription: String? {
        switch self {
        case .stale: "The document, selection, or canvas changed before the semantic element could commit."
        case .cancelled: "The semantic element draft was cancelled; committed metadata is unchanged."
        case .invalidElement: "That HTML element is not supported for this object kind."
        case .unavailable(let reason): reason
        case .noApplicableTargets: "The selection has no supported authored object for semantic HTML."
        case .noChanges: "The semantic HTML element already has that value."
        }
    }
}

struct SemanticElementCommandRegistry: Sendable {
    static let requirementIDs = Set((1...8).map { String(format: "SF-1203-%03d", $0) })

    static func resolvedElement(for node: DocumentNode) -> (SemanticHTMLElement, PropertyOrigin)? {
        guard let fallback = CanonicalSemanticElement.defaultElement(for: node.kind) else { return nil }
        guard let property = node.insertionProperty(CanonicalSemanticElement.key) else { return (fallback, .defaulted) }
        guard case .string(let raw) = property.value,
              let element = SemanticHTMLElement(rawValue: raw),
              CanonicalSemanticElement.supportedElements(for: node.kind).contains(element) else { return nil }
        return (element, property.origin)
    }

    static func selectionValue(nodes: [DocumentNode]) -> SemanticElementInspectorValue {
        guard !nodes.isEmpty else { return .unavailable("Select an authored object to edit its semantic HTML element.") }
        let applicable = nodes.compactMap { node -> (DocumentNode, SemanticHTMLElement, PropertyOrigin)? in
            guard let resolved = resolvedElement(for: node) else { return nil }
            return (node, resolved.0, resolved.1)
        }
        guard !applicable.isEmpty else { return .unavailable("Component instances do not own semantic HTML metadata in this milestone.") }
        guard let first = applicable.first,
              applicable.dropFirst().allSatisfy({ $0.1 == first.1 && $0.2 == first.2 }) else {
            return .mixed(applicableCount: applicable.count, skippedCount: nodes.count - applicable.count)
        }
        return .single(first.1, first.2)
    }

    func prepare(_ command: SemanticElementCommand, in document: CanonicalDocument, context: TransformValidationContext) throws -> PreparedDesignInspectorEdit {
        guard !command.cancelled else { throw SemanticElementCommandError.cancelled }
        guard context.isLifecycleAvailable else { throw SemanticElementCommandError.unavailable(context.lifecycleDisabledReason ?? "Semantic HTML editing is unavailable.") }
        guard command.identity.documentID == document.id,
              command.identity.pageID == context.activePageID,
              command.identity.revision == document.revision,
              command.identity.sceneID == context.currentSceneID,
              command.identity.rendererGeneration == context.rendererGeneration,
              command.orderedNodeIDs == context.selectedNodeIDs,
              !command.orderedNodeIDs.isEmpty,
              Set(command.orderedNodeIDs).count == command.orderedNodeIDs.count,
              let page = document.pages.first(where: { $0.id == command.identity.pageID }) else {
            throw SemanticElementCommandError.stale
        }
        var applicable: [NodeID] = [], skipped: [NodeID] = [], reasons: [NodeID: String] = [:]
        var changes: [DocumentCommand] = []
        for id in command.orderedNodeIDs {
            guard let node = page.nodes.first(where: { $0.id == id }) else { throw SemanticElementCommandError.stale }
            guard context.availableNodeIDs.contains(id), !node.selectionBooleanProperty("hidden"), !node.selectionBooleanProperty("locked") else {
                throw SemanticElementCommandError.unavailable("A selected object is unavailable, hidden, or locked.")
            }
            guard let current = Self.resolvedElement(for: node) else {
                skipped.append(id); reasons[id] = "This object does not own semantic HTML metadata."; continue
            }
            applicable.append(id)
            let old = node.insertionProperty(CanonicalSemanticElement.key)
            switch command.edit {
            case .set(let element):
                guard CanonicalSemanticElement.supportedElements(for: node.kind).contains(element) else {
                    // Mixed selection follows the established Inspector rule:
                    // mutate only compatible targets and explain every skip.
                    applicable.removeLast()
                    skipped.append(id)
                    reasons[id] = "This HTML element is not supported for this object kind."
                    continue
                }
                if current.0 != element || current.1 != .authored {
                    changes.append(.setProperty(.init(pageID: page.id, nodeID: id,
                        property: .init(id: old?.id ?? PropertyID(), key: .init(rawValue: CanonicalSemanticElement.key), value: .string(element.rawValue), origin: .authored))))
                }
            case .reset:
                if let old { changes.append(.removeProperty(.init(pageID: page.id, nodeID: id, propertyID: old.id))) }
            }
        }
        guard !applicable.isEmpty else { throw SemanticElementCommandError.noApplicableTargets }
        guard !changes.isEmpty else { throw SemanticElementCommandError.noChanges }
        let batch: DocumentCommand = .batch(changes)
        guard CommandRegistry().availability(for: batch, in: document).isEnabled else { throw SemanticElementCommandError.stale }
        return .init(applicableNodeIDs: applicable, skippedNodeIDs: skipped, skippedReasons: reasons, documentCommand: batch)
    }
}
