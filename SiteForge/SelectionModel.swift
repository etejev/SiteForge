import Foundation

enum SelectionProvenance: String, Sendable {
    case pointer
    case keyboard
    case menu
    case contextualMenu
    case layersNavigator
    case accessibility
    case lifecycleRepair
}

enum SelectionPointerModifier: Sendable {
    case replace
    case add
    case toggle
}

extension DocumentNode {
    func selectionBooleanProperty(_ key: String) -> Bool {
        properties.first(where: { $0.key.rawValue == key }).flatMap { property in
            if case .boolean(let value) = property.value { return value }
            return nil
        } ?? false
    }
}

enum SelectionRepairCategory: String, Sendable {
    case none
    case documentChanged
    case pageChanged
    case removed
    case hidden
    case locked
    case clipped
    case unavailable
    case scopeChanged
    case sceneReplaced
}

enum SelectionLifecycleBoundary: String, Sendable {
    case documentAdoption
    case save
    case reopen
    case autosave
    case recovery
    case undo
    case redo
    case pageSwitch
    case rendererGeneration
    case sceneReplacement
}

struct SelectionTargetSnapshot: Equatable, Sendable {
    let id: NodeID
    let pageID: PageID
    let parentID: NodeID?
    let name: String
    let kind: NodeKind
    let parentName: String?
    let frame: WorldRect
    let clipRect: WorldRect?
    let paintOrder: Int
    let isVisible: Bool
    let isLocked: Bool
    let isAvailable: Bool

    init(
        id: NodeID,
        pageID: PageID,
        parentID: NodeID?,
        name: String,
        kind: NodeKind = .frame,
        parentName: String? = nil,
        frame: WorldRect,
        clipRect: WorldRect?,
        paintOrder: Int,
        isVisible: Bool,
        isLocked: Bool,
        isAvailable: Bool
    ) {
        self.id = id
        self.pageID = pageID
        self.parentID = parentID
        self.name = name
        self.kind = kind
        self.parentName = parentName
        self.frame = frame
        self.clipRect = clipRect
        self.paintOrder = paintOrder
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.isAvailable = isAvailable
    }

    var isFullyClipped: Bool {
        guard let clipRect else { return false }
        return frame.maxX <= clipRect.minX || frame.minX >= clipRect.maxX
            || frame.maxY <= clipRect.minY || frame.minY >= clipRect.maxY
    }

    var isSelectable: Bool { isAvailable && isVisible && !isFullyClipped }
}

struct SelectionSceneSnapshot: Equatable, Sendable {
    let identity: CanvasRenderRequestIdentity
    let activePageID: PageID
    let activeContainerID: NodeID?
    let targets: [SelectionTargetSnapshot]

    var orderedSelectableTargets: [SelectionTargetSnapshot] {
        targets.filter { target in
            target.pageID == activePageID
                && target.parentID == activeContainerID
                && target.isSelectable
        }.sorted {
            $0.paintOrder == $1.paintOrder
                ? $0.id.description < $1.id.description
                : $0.paintOrder < $1.paintOrder
        }
    }
}

struct SelectionState: Equatable, Sendable {
    private(set) var orderedIDs: [NodeID] = []
    private(set) var primaryID: NodeID?
    private(set) var anchorID: NodeID?
    private(set) var activePageID: PageID?
    private(set) var activeContainerID: NodeID?
    private(set) var provenance: SelectionProvenance = .lifecycleRepair
    private(set) var sceneIdentity: CanvasRenderRequestIdentity?
    private(set) var lastRepair: SelectionRepairCategory = .none

    var isEmpty: Bool { orderedIDs.isEmpty }
    var count: Int { orderedIDs.count }

    mutating func establishScene(_ scene: SelectionSceneSnapshot) {
        activePageID = scene.activePageID
        activeContainerID = scene.activeContainerID
        sceneIdentity = scene.identity
    }

    mutating func setSelection(
        _ ids: [NodeID],
        primary: NodeID?,
        anchor: NodeID?,
        provenance: SelectionProvenance,
        repair: SelectionRepairCategory = .none
    ) {
        orderedIDs = ids
        primaryID = primary
        anchorID = anchor
        self.provenance = provenance
        lastRepair = repair
    }

    mutating func setContainer(_ id: NodeID?) { activeContainerID = id }
}

enum SelectionCommandName: String, CaseIterable, Sendable {
    case replace
    case add
    case toggle
    case clear
    case next
    case previous
    case escape
}

struct SelectionCommand: Equatable, Sendable {
    let name: SelectionCommandName
    let targetID: NodeID?
    let expectedIdentity: CanvasRenderRequestIdentity
    let provenance: SelectionProvenance

    init(
        _ name: SelectionCommandName,
        targetID: NodeID? = nil,
        expectedIdentity: CanvasRenderRequestIdentity,
        provenance: SelectionProvenance
    ) {
        self.name = name
        self.targetID = targetID
        self.expectedIdentity = expectedIdentity
        self.provenance = provenance
    }
}

enum SelectionCommandError: Error, Equatable, LocalizedError, Sendable {
    case staleScene
    case duplicateSceneTarget(NodeID)
    case missingTarget
    case duplicateTarget(NodeID)
    case hiddenTarget(NodeID)
    case clippedTarget(NodeID)
    case unavailableTarget(NodeID)
    case outsideActiveScope(NodeID)
    case invalidState
    case disabled(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .staleScene: "A newer rendered scene replaced this selection command."
        case .duplicateSceneTarget, .invalidState: "The selection scene is internally inconsistent."
        case .missingTarget: "The selection target no longer exists."
        case .duplicateTarget: "The object is already selected."
        case .hiddenTarget: "Hidden objects cannot be selected from the canvas or Layers."
        case .clippedTarget: "The object is outside the selectable clipped region."
        case .unavailableTarget: "The object is temporarily unavailable."
        case .outsideActiveScope: "The object is outside the active page or container."
        case .disabled(let reason): reason
        case .cancelled: "Selection was cancelled; the last valid selection remains active."
        }
    }
}

struct SelectionCommandAvailability: Equatable, Sendable {
    let isEnabled: Bool
    let disabledReason: String?
    static let enabled = SelectionCommandAvailability(isEnabled: true, disabledReason: nil)
    static func disabled(_ reason: String) -> Self { Self(isEnabled: false, disabledReason: reason) }
}

enum SelectionCommandResult: Equatable, Sendable {
    case changed
    case unchanged
}

struct SelectionCancellation: Sendable {
    let isCancelled: @Sendable () -> Bool
    static let never = SelectionCancellation(isCancelled: { false })
}

struct SelectionCommandRegistry: Sendable {
    static let requirementIDs: Set<String> = [
        "SF-0402-001", "SF-0402-002", "SF-0402-003", "SF-0402-004",
        "SF-0402-005", "SF-0402-006", "SF-0402-007", "SF-0402-008",
    ]

    func availability(
        for command: SelectionCommand,
        state: SelectionState,
        scene: SelectionSceneSnapshot
    ) -> SelectionCommandAvailability {
        do {
            try validateScene(scene)
            guard command.expectedIdentity == scene.identity,
                  state.sceneIdentity == scene.identity else {
                return .disabled("A newer canvas scene owns selection.")
            }
            switch command.name {
            case .replace, .add, .toggle:
                guard let targetID = command.targetID else { return .disabled("A selection target is required.") }
                do { _ = try target(targetID, in: scene) }
                catch { return .disabled(error.localizedDescription) }
                if command.name == .add, state.orderedIDs.contains(targetID) {
                    return .disabled("The object is already selected.")
                }
                return .enabled
            case .clear:
                return state.isEmpty ? .disabled("There is no selection to clear.") : .enabled
            case .next, .previous:
                return scene.orderedSelectableTargets.isEmpty
                    ? .disabled("There are no selectable objects in the active scope.") : .enabled
            case .escape:
                return state.isEmpty && state.activeContainerID == nil
                    ? .disabled("There is no selection or container scope to exit.") : .enabled
            }
        } catch {
            return .disabled(error.localizedDescription)
        }
    }

    @discardableResult
    func apply(
        _ command: SelectionCommand,
        to state: inout SelectionState,
        scene: SelectionSceneSnapshot,
        cancellation: SelectionCancellation = .never
    ) throws -> SelectionCommandResult {
        guard !cancellation.isCancelled() else { throw SelectionCommandError.cancelled }
        try validateScene(scene)
        guard command.expectedIdentity == scene.identity,
              state.sceneIdentity == scene.identity else { throw SelectionCommandError.staleScene }
        let availability = availability(for: command, state: state, scene: scene)
        guard availability.isEnabled else {
            throw SelectionCommandError.disabled(availability.disabledReason ?? "Selection is unavailable.")
        }
        var draft = state
        switch command.name {
        case .replace:
            let id = try requiredTarget(command, scene: scene).id
            draft.setSelection([id], primary: id, anchor: id, provenance: command.provenance)
        case .add:
            let id = try requiredTarget(command, scene: scene).id
            guard !draft.orderedIDs.contains(id) else { throw SelectionCommandError.duplicateTarget(id) }
            draft.setSelection(
                draft.orderedIDs + [id], primary: id,
                anchor: draft.anchorID ?? id, provenance: command.provenance
            )
        case .toggle:
            let id = try requiredTarget(command, scene: scene).id
            if let index = draft.orderedIDs.firstIndex(of: id) {
                var ids = draft.orderedIDs
                ids.remove(at: index)
                draft.setSelection(
                    ids, primary: ids.last,
                    anchor: draft.anchorID == id ? ids.first : draft.anchorID,
                    provenance: command.provenance
                )
            } else {
                draft.setSelection(
                    draft.orderedIDs + [id], primary: id,
                    anchor: draft.anchorID ?? id, provenance: command.provenance
                )
            }
        case .clear:
            draft.setSelection([], primary: nil, anchor: nil, provenance: command.provenance)
        case .next, .previous:
            let targets = scene.orderedSelectableTargets
            let offset = command.name == .next ? 1 : -1
            let index: Int
            if let primary = draft.primaryID, let current = targets.firstIndex(where: { $0.id == primary }) {
                index = (current + offset + targets.count) % targets.count
            } else {
                index = command.name == .next ? 0 : targets.count - 1
            }
            let id = targets[index].id
            draft.setSelection([id], primary: id, anchor: id, provenance: command.provenance)
        case .escape:
            if !draft.isEmpty {
                draft.setSelection([], primary: nil, anchor: nil, provenance: command.provenance)
            } else {
                draft.setContainer(nil)
            }
        }
        guard !cancellation.isCancelled() else { throw SelectionCommandError.cancelled }
        try validateState(draft, scene: scene)
        let result: SelectionCommandResult = draft == state ? .unchanged : .changed
        state = draft
        return result
    }

    @discardableResult
    func adopt(
        _ scene: SelectionSceneSnapshot,
        boundary: SelectionLifecycleBoundary,
        state: inout SelectionState
    ) throws -> SelectionRepairCategory {
        try validateScene(scene)
        let prior = state
        state.establishScene(scene)
        if prior.sceneIdentity?.documentID != nil,
           prior.sceneIdentity?.documentID != scene.identity.documentID {
            state.setSelection([], primary: nil, anchor: nil, provenance: .lifecycleRepair, repair: .documentChanged)
            return .documentChanged
        }
        if prior.activePageID != nil, prior.activePageID != scene.activePageID {
            state.setSelection([], primary: nil, anchor: nil, provenance: .lifecycleRepair, repair: .pageChanged)
            return .pageChanged
        }
        let catalog = Dictionary(uniqueKeysWithValues: scene.targets.map { ($0.id, $0) })
        var repair: SelectionRepairCategory = boundary == .sceneReplacement ? .sceneReplaced : .none
        let retained = prior.orderedIDs.filter { id in
            guard let value = catalog[id] else { repair = .removed; return false }
            guard value.pageID == scene.activePageID, value.parentID == scene.activeContainerID else {
                repair = .scopeChanged; return false
            }
            guard value.isAvailable else { repair = .unavailable; return false }
            guard value.isVisible else { repair = .hidden; return false }
            guard !value.isFullyClipped else { repair = .clipped; return false }
            return true
        }
        let primary = prior.primaryID.flatMap { retained.contains($0) ? $0 : nil } ?? retained.last
        let anchor = prior.anchorID.flatMap { retained.contains($0) ? $0 : nil } ?? retained.first
        state.setSelection(
            retained, primary: primary, anchor: anchor,
            provenance: repair == .none ? prior.provenance : .lifecycleRepair,
            repair: repair
        )
        return repair
    }

    private func requiredTarget(
        _ command: SelectionCommand,
        scene: SelectionSceneSnapshot
    ) throws -> SelectionTargetSnapshot {
        guard let id = command.targetID else { throw SelectionCommandError.missingTarget }
        return try target(id, in: scene)
    }

    private func target(_ id: NodeID, in scene: SelectionSceneSnapshot) throws -> SelectionTargetSnapshot {
        guard let target = scene.targets.first(where: { $0.id == id }) else {
            throw SelectionCommandError.missingTarget
        }
        guard target.pageID == scene.activePageID, target.parentID == scene.activeContainerID else {
            throw SelectionCommandError.outsideActiveScope(id)
        }
        guard target.isAvailable else { throw SelectionCommandError.unavailableTarget(id) }
        guard target.isVisible else { throw SelectionCommandError.hiddenTarget(id) }
        guard !target.isFullyClipped else { throw SelectionCommandError.clippedTarget(id) }
        return target
    }

    private func validateScene(_ scene: SelectionSceneSnapshot) throws {
        guard scene.targets.count <= CanvasRendererPolicy.maximumObjects else {
            throw SelectionCommandError.invalidState
        }
        var ids = Set<NodeID>()
        for target in scene.targets {
            guard ids.insert(target.id).inserted else {
                throw SelectionCommandError.duplicateSceneTarget(target.id)
            }
        }
    }

    private func validateState(_ state: SelectionState, scene: SelectionSceneSnapshot) throws {
        guard Set(state.orderedIDs).count == state.orderedIDs.count,
              state.primaryID.map(state.orderedIDs.contains) ?? state.orderedIDs.isEmpty,
              state.anchorID.map(state.orderedIDs.contains) ?? state.orderedIDs.isEmpty else {
            throw SelectionCommandError.invalidState
        }
        for id in state.orderedIDs { _ = try target(id, in: scene) }
    }
}

struct SelectionOverlayPlan: Equatable, Sendable {
    let identity: CanvasRenderRequestIdentity
    let overlays: [CanvasEditorOverlay]
    let dirtyWorldRegions: [WorldRect]
    let authoredContentInvalidated: Bool
}

struct SelectionOverlayPlanner: Sendable {
    func plan(
        selection: SelectionState,
        scene: SelectionSceneSnapshot,
        renderPlan: CanvasRenderPlan,
        previous: SelectionOverlayPlan? = nil
    ) throws -> SelectionOverlayPlan {
        guard selection.sceneIdentity == scene.identity,
              renderPlan.identity == scene.identity else { throw SelectionCommandError.staleScene }
        let targets = Dictionary(uniqueKeysWithValues: scene.targets.map { ($0.id, $0) })
        let overlays = selection.orderedIDs.compactMap { id -> CanvasEditorOverlay? in
            guard let target = targets[id], target.isSelectable else { return nil }
            let frame = clippedFrame(target.frame, to: target.clipRect)
            let primary = selection.primaryID == id
            let kind = primary
                ? (target.isLocked ? "selection-primary-locked" : "selection-primary")
                : (target.isLocked ? "selection-secondary-locked" : "selection-secondary")
            let label: String?
            if primary, target.kind == .frame {
                let parent = target.parentName ?? "Page"
                label = "\(target.name) · \(Int(target.frame.size.width)) × \(Int(target.frame.size.height)) · \(parent)"
            } else {
                label = nil
            }
            return CanvasEditorOverlay(
                id: CanvasOverlayID(id.rawValue),
                objectID: id,
                frame: frame,
                kind: kind,
                label: label
            )
        }
        let oldFrames = previous?.overlays.map(\.frame) ?? []
        let dirty = uniqueRegions(oldFrames + overlays.map(\.frame))
        return SelectionOverlayPlan(
            identity: scene.identity,
            overlays: overlays,
            dirtyWorldRegions: dirty,
            authoredContentInvalidated: false
        )
    }

    private func clippedFrame(_ frame: WorldRect, to clip: WorldRect?) -> WorldRect {
        guard let clip else { return frame }
        let minX = max(frame.minX, clip.minX)
        let minY = max(frame.minY, clip.minY)
        let maxX = min(frame.maxX, clip.maxX)
        let maxY = min(frame.maxY, clip.maxY)
        guard maxX > minX, maxY > minY else { return frame }
        return WorldRect(
            origin: WorldPoint(x: minX, y: minY),
            size: WorldSize(width: maxX - minX, height: maxY - minY)
        )
    }

    private func uniqueRegions(_ regions: [WorldRect]) -> [WorldRect] {
        var seen = Set<String>()
        return regions.filter { region in
            seen.insert("\(region.minX),\(region.minY),\(region.maxX),\(region.maxY)").inserted
        }
    }
}

enum SelectionDiagnosticResult: String, Codable, Sendable { case success, failure, cancelled, stale }

struct SelectionDiagnosticRecord: Codable, Equatable, Sendable {
    let requirementID: String
    let operation: String
    let sanitizedIdentifiers: [String]
    let durationMilliseconds: Double
    let selectionCount: Int
    let repairCategory: String?
    let failureCategory: String?
    let result: SelectionDiagnosticResult
}

actor SelectionDiagnostics {
    private var records: [SelectionDiagnosticRecord] = []
    func append(_ record: SelectionDiagnosticRecord) { records.append(record) }
    func snapshot() -> [SelectionDiagnosticRecord] { records }
}

enum SelectionDiagnosticFactory {
    static func make(
        operation: SelectionCommandName,
        state: SelectionState,
        durationMilliseconds: Double,
        result: SelectionDiagnosticResult,
        repair: SelectionRepairCategory? = nil,
        failure: String? = nil
    ) -> SelectionDiagnosticRecord {
        SelectionDiagnosticRecord(
            requirementID: "SF-0402-008",
            operation: operation.rawValue,
            sanitizedIdentifiers: state.orderedIDs.prefix(32).map { String($0.description.prefix(8)) },
            durationMilliseconds: max(0, durationMilliseconds),
            selectionCount: state.count,
            repairCategory: repair.map(\.rawValue),
            failureCategory: failure.map(sanitizedFailureCategory),
            result: result
        )
    }

    private static func sanitizedFailureCategory(_ value: String) -> String {
        let normalized = value.lowercased()
        if normalized.contains("stale") { return "stale-scene" }
        if normalized.contains("cancel") { return "cancelled" }
        if normalized.contains("hidden") { return "hidden-target" }
        if normalized.contains("clip") { return "clipped-target" }
        if normalized.contains("unavailable") { return "unavailable-target" }
        if normalized.contains("scope") { return "outside-active-scope" }
        if normalized.contains("duplicate") { return "duplicate-target" }
        if normalized.contains("missing") { return "missing-target" }
        return "selection-failure"
    }
}
