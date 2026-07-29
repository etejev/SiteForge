import Foundation

// SF-0406-001...008 — bounded inline plain-text editing foundation.

private extension DocumentNode {
    func textEditingBooleanProperty(_ key: String) -> Bool {
        properties.first(where: { $0.key.rawValue == key }).flatMap { property in
            if case .boolean(let value) = property.value { return value }
            return nil
        } ?? false
    }
}

enum TextEditSessionIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "text-edit-session"
}
typealias TextEditSessionID = StableIdentifier<TextEditSessionIdentifierDomain>

enum TextEditProvenance: String, CaseIterable, Sendable {
    case pointer
    case keyboard
    case menu
    case contextualMenu
    case accessibility
    case automation
}

struct TextEditRange: Equatable, Sendable {
    let location: Int
    let length: Int

    static let zero = TextEditRange(location: 0, length: 0)
    var upperBound: Int { location + length }

    func isValid(in text: String) -> Bool {
        guard location >= 0, length >= 0, upperBound >= location else { return false }
        guard upperBound <= text.utf16.count else { return false }
        var foundStart = location == text.utf16.count
        var foundEnd = upperBound == text.utf16.count
        for index in text.indices {
            let offset = index.utf16Offset(in: text)
            foundStart = foundStart || offset == location
            foundEnd = foundEnd || offset == upperBound
            if foundStart && foundEnd { return true }
            if offset > upperBound { break }
        }
        return foundStart && foundEnd
    }
}

struct TextEditOperationIdentity: Equatable, Sendable {
    let sessionID: TextEditSessionID
    let documentID: DocumentID
    let pageID: PageID
    let revision: UInt64
    let sceneID: CanvasViewportSceneID
    let rendererGeneration: UInt64
    let nodeID: NodeID
}

struct TextEditValidationContext: Sendable {
    let activePageID: PageID
    let sceneID: CanvasViewportSceneID
    let rendererGeneration: UInt64
    let availableNodeIDs: Set<NodeID>?
    let isLifecycleAvailable: Bool
    let lifecycleDisabledReason: String?
}

enum TextEditError: Error, Equatable, LocalizedError, Sendable {
    case lifecycleUnavailable(String)
    case staleDocument
    case stalePage
    case staleRevision
    case staleRenderer
    case missingNode
    case incompatibleNode
    case lockedNode
    case hiddenNode
    case unavailableNode
    case invalidText
    case textLimitExceeded
    case invalidSelection
    case activeComposition
    case cancelled
    case revisionExhausted
    case invalidResult

    var errorDescription: String? {
        switch self {
        case .lifecycleUnavailable(let reason): reason
        case .staleDocument: "A different document now owns this text edit."
        case .stalePage: "The edited text node is no longer on the active page."
        case .staleRevision: "The document changed before this text edit could commit."
        case .staleRenderer: "A newer rendered scene replaced this text edit."
        case .missingNode: "The text node no longer exists."
        case .incompatibleNode: "Only a plain-text node can be edited in this foundation."
        case .lockedNode: "The text node is locked. Unlock it before editing."
        case .hiddenNode: "The text node is hidden. Show it before editing."
        case .unavailableNode: "The text node is unavailable in the current rendered scene."
        case .invalidText: "Plain text contains unsupported control input."
        case .textLimitExceeded: "Plain text exceeds the bounded 64 KiB UTF-8 limit."
        case .invalidSelection: "The text selection does not align with valid character boundaries."
        case .activeComposition: "Finish the current input-method composition before committing."
        case .cancelled: "Text editing was cancelled; committed text is unchanged."
        case .revisionExhausted: "The document revision cannot accept another text edit."
        case .invalidResult: "The text edit could not produce a valid document."
        }
    }
}

struct TextEditAvailability: Equatable, Sendable {
    let isEnabled: Bool
    let disabledReason: String?
    static let enabled = Self(isEnabled: true, disabledReason: nil)
    static func disabled(_ reason: String) -> Self { Self(isEnabled: false, disabledReason: reason) }
}

struct TextEditCancellation: Sendable {
    let isCancelled: @Sendable () -> Bool
    static let never = Self(isCancelled: { false })
}

struct TextEditActivation: Equatable, Sendable {
    let identity: TextEditOperationIdentity
    let propertyID: PropertyID
    let originalText: String
    let originalOrigin: PropertyOrigin
    let provenance: TextEditProvenance
}

struct TextEditDraft: Equatable, Sendable {
    let activation: TextEditActivation
    var text: String
    var selection: TextEditRange
    var markedRange: TextEditRange?

    var hasChanges: Bool { text != activation.originalText }
}

struct PreparedTextEdit: Equatable, Sendable {
    let identity: TextEditOperationIdentity
    let originalText: String
    let committedText: String
    let command: DocumentCommand?
}

struct InlineTextEditorPresentation: Equatable, Sendable {
    let identity: TextEditOperationIdentity
    let text: String
    let selection: TextEditRange
    let frame: WorldRect
}

enum InlineTextEditingPolicy {
    static let maximumTextBytes = InsertionPolicy.maximumTextBytes

    static func validatesContent(_ text: String) -> Bool {
        !text.unicodeScalars.contains {
            $0.value < 0x20 && $0 != "\n" && $0 != "\t"
        }
    }
}

enum TextEditKey: Equatable, Sendable {
    case returnKey
    case escape
    case other
}

enum TextEditKeyRoutingDecision: Equatable, Sendable {
    case commit
    case cancel
    case passThrough
}

enum TextEditKeyRoutingPolicy {
    static func decision(
        key: TextEditKey,
        isCommandModified: Bool,
        hasUnsupportedModifiers: Bool,
        isEditing: Bool,
        hasMarkedText: Bool
    ) -> TextEditKeyRoutingDecision {
        guard isEditing, !hasUnsupportedModifiers else { return .passThrough }
        switch (key, isCommandModified, hasMarkedText) {
        case (.returnKey, true, false): return .commit
        case (.escape, false, _): return .cancel
        default: return .passThrough
        }
    }
}

struct InlineTextCommandRegistry: Sendable {
    static let requirementIDs: Set<String> = [
        "SF-0406-001", "SF-0406-002", "SF-0406-003", "SF-0406-004",
        "SF-0406-005", "SF-0406-006", "SF-0406-007", "SF-0406-008",
    ]

    func availability(
        nodeID: NodeID,
        provenance: TextEditProvenance,
        in document: CanonicalDocument,
        context: TextEditValidationContext
    ) -> TextEditAvailability {
        do {
            _ = try activate(
                nodeID: nodeID,
                provenance: provenance,
                in: document,
                context: context
            )
            return .enabled
        } catch {
            return .disabled(error.localizedDescription)
        }
    }

    func activate(
        nodeID: NodeID,
        provenance: TextEditProvenance,
        in document: CanonicalDocument,
        context: TextEditValidationContext,
        cancellation: TextEditCancellation = .never
    ) throws -> TextEditActivation {
        try validateIdentity(document: document, context: context, cancellation: cancellation)
        guard let page = document.pages.first(where: { $0.id == context.activePageID }),
              let node = page.nodes.first(where: { $0.id == nodeID }) else {
            if document.pages.flatMap(\.nodes).contains(where: { $0.id == nodeID }) {
                throw TextEditError.stalePage
            }
            throw TextEditError.missingNode
        }
        guard node.kind == .text else { throw TextEditError.incompatibleNode }
        guard !node.textEditingBooleanProperty("locked") else { throw TextEditError.lockedNode }
        guard !node.textEditingBooleanProperty("hidden") else { throw TextEditError.hiddenNode }
        if let available = context.availableNodeIDs, !available.contains(nodeID) {
            throw TextEditError.unavailableNode
        }
        guard let property = node.properties.first(where: {
            $0.key.rawValue == "content.text"
        }), case .string(let text) = property.value else {
            throw TextEditError.incompatibleNode
        }
        try validate(text: text, selection: TextEditRange(
            location: (text as NSString).length,
            length: 0
        ))
        return TextEditActivation(
            identity: TextEditOperationIdentity(
                sessionID: TextEditSessionID(),
                documentID: document.id,
                pageID: page.id,
                revision: document.revision,
                sceneID: context.sceneID,
                rendererGeneration: context.rendererGeneration,
                nodeID: nodeID
            ),
            propertyID: property.id,
            originalText: text,
            originalOrigin: property.origin,
            provenance: provenance
        )
    }

    func prepare(
        _ draft: TextEditDraft,
        in document: CanonicalDocument,
        context: TextEditValidationContext,
        cancellation: TextEditCancellation = .never
    ) throws -> PreparedTextEdit {
        guard draft.markedRange == nil else { throw TextEditError.activeComposition }
        try validateIdentity(
            draft.activation.identity,
            document: document,
            context: context,
            cancellation: cancellation
        )
        try validate(text: draft.text, selection: draft.selection)
        guard let page = document.pages.first(where: {
            $0.id == draft.activation.identity.pageID
        }), let node = page.nodes.first(where: {
            $0.id == draft.activation.identity.nodeID
        }) else { throw TextEditError.missingNode }
        guard node.kind == .text else { throw TextEditError.incompatibleNode }
        guard !node.textEditingBooleanProperty("locked") else { throw TextEditError.lockedNode }
        guard !node.textEditingBooleanProperty("hidden") else { throw TextEditError.hiddenNode }
        if let available = context.availableNodeIDs,
           !available.contains(draft.activation.identity.nodeID) {
            throw TextEditError.unavailableNode
        }
        guard let property = node.properties.first(where: {
            $0.id == draft.activation.propertyID
                && $0.key.rawValue == "content.text"
        }), case .string(let current) = property.value,
              current == draft.activation.originalText else {
            throw TextEditError.staleRevision
        }
        let command: DocumentCommand? = draft.hasChanges
            ? .setProperty(SetPropertyCommand(
                pageID: draft.activation.identity.pageID,
                nodeID: draft.activation.identity.nodeID,
                property: NodeProperty(
                    id: property.id,
                    key: property.key,
                    value: .string(draft.text),
                    origin: .authored
                )
            ))
            : nil
        if let command,
           !CommandRegistry().availability(for: command, in: document).isEnabled {
            throw TextEditError.invalidResult
        }
        return PreparedTextEdit(
            identity: draft.activation.identity,
            originalText: draft.activation.originalText,
            committedText: draft.text,
            command: command
        )
    }

    private func validateIdentity(
        document: CanonicalDocument,
        context: TextEditValidationContext,
        cancellation: TextEditCancellation
    ) throws {
        guard !cancellation.isCancelled() else { throw TextEditError.cancelled }
        guard context.isLifecycleAvailable else {
            throw TextEditError.lifecycleUnavailable(
                context.lifecycleDisabledReason ?? "Text editing is unavailable."
            )
        }
        guard document.pages.contains(where: { $0.id == context.activePageID }) else {
            throw TextEditError.stalePage
        }
    }

    private func validateIdentity(
        _ identity: TextEditOperationIdentity,
        document: CanonicalDocument,
        context: TextEditValidationContext,
        cancellation: TextEditCancellation
    ) throws {
        try validateIdentity(document: document, context: context, cancellation: cancellation)
        guard identity.documentID == document.id else { throw TextEditError.staleDocument }
        guard identity.pageID == context.activePageID else { throw TextEditError.stalePage }
        guard identity.revision == document.revision else { throw TextEditError.staleRevision }
        guard identity.sceneID == context.sceneID,
              identity.rendererGeneration == context.rendererGeneration else {
            throw TextEditError.staleRenderer
        }
    }

    private func validate(text: String, selection: TextEditRange) throws {
        guard text.utf8.count <= InlineTextEditingPolicy.maximumTextBytes else {
            throw TextEditError.textLimitExceeded
        }
        guard InlineTextEditingPolicy.validatesContent(text) else {
            throw TextEditError.invalidText
        }
        guard selection.isValid(in: text) else { throw TextEditError.invalidSelection }
    }
}

enum InlineTextEditingPhase: Equatable, Sendable {
    case inactive
    case drafting(TextEditDraft)
    case previewing(TextEditDraft)
    case composing(TextEditDraft)
    case committing(TextEditDraft)
    case cancelled
    case failed(TextEditError, TextEditDraft?)
}

struct InlineTextEditingSession: Equatable, Sendable {
    private(set) var phase: InlineTextEditingPhase = .inactive

    var draft: TextEditDraft? {
        switch phase {
        case .drafting(let value), .previewing(let value), .composing(let value),
             .committing(let value):
            value
        case .failed(_, let value): value
        case .inactive, .cancelled: nil
        }
    }

    var isActive: Bool { draft != nil }

    mutating func begin(_ activation: TextEditActivation) {
        let end = (activation.originalText as NSString).length
        phase = .drafting(TextEditDraft(
            activation: activation,
            text: activation.originalText,
            selection: TextEditRange(location: end, length: 0),
            markedRange: nil
        ))
    }

    mutating func update(text: String, selection: TextEditRange, markedRange: TextEditRange?) {
        guard var value = draft else { return }
        value.text = text
        value.selection = selection
        value.markedRange = markedRange
        phase = markedRange == nil ? .previewing(value) : .composing(value)
    }

    mutating func beginCommit() {
        guard let value = draft else { return }
        phase = .committing(value)
    }

    mutating func complete() { phase = .inactive }
    mutating func cancel() { phase = .cancelled }
    mutating func fail(_ error: TextEditError) { phase = .failed(error, draft) }
}

enum TextEditDiagnosticResult: String, Sendable {
    case success
    case cancelled
    case stale
    case failure
}

struct TextEditDiagnosticRecord: Equatable, Sendable {
    let requirementIDs: [String]
    let operation: String
    let identities: [String]
    let durationMilliseconds: Double
    let originalUTF8Bytes: Int
    let resultUTF8Bytes: Int?
    let result: TextEditDiagnosticResult
    let failureCategory: String?
}

actor TextEditDiagnostics {
    private var records: [TextEditDiagnosticRecord] = []
    func append(_ record: TextEditDiagnosticRecord) { records.append(record) }
    func snapshot() -> [TextEditDiagnosticRecord] { records }
}

enum TextEditDiagnosticFactory {
    static func makeActivationFailure(
        nodeID: NodeID,
        pageID: PageID,
        durationMilliseconds: Double,
        failure: TextEditError
    ) -> TextEditDiagnosticRecord {
        TextEditDiagnosticRecord(
            requirementIDs: InlineTextCommandRegistry.requirementIDs.sorted(),
            operation: "activate",
            identities: [nodeID.description, pageID.description],
            durationMilliseconds: durationMilliseconds,
            originalUTF8Bytes: 0,
            resultUTF8Bytes: nil,
            result: [.staleDocument, .stalePage, .staleRevision, .staleRenderer]
                .contains(failure) ? .stale : .failure,
            failureCategory: String(describing: failure)
        )
    }

    static func make(
        operation: String,
        draft: TextEditDraft,
        durationMilliseconds: Double,
        result: TextEditDiagnosticResult,
        failure: TextEditError?
    ) -> TextEditDiagnosticRecord {
        TextEditDiagnosticRecord(
            requirementIDs: InlineTextCommandRegistry.requirementIDs.sorted(),
            operation: operation,
            identities: [
                draft.activation.identity.sessionID.description,
                draft.activation.identity.nodeID.description,
                draft.activation.identity.pageID.description,
            ],
            durationMilliseconds: durationMilliseconds,
            originalUTF8Bytes: draft.activation.originalText.utf8.count,
            resultUTF8Bytes: result == .success ? draft.text.utf8.count : nil,
            result: result,
            failureCategory: failure.map { String(describing: $0) }
        )
    }
}
