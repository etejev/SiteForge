import CryptoKit
import Foundation

// SF-0308-001...008. Clipboard bytes are an inert, bounded transfer envelope.
// They are never part of the canonical document or project package; only the
// validated result is compiled into the existing document command registry.
struct SiteForgeClipboardEnvelope: Codable, Equatable, Sendable {
    private static let versionWithoutUsageNotes = 2
    private static let versionWithDecorativeData = 4
    /// Version 5 carries reusable styles with linked box appearance (SF-0510)
    /// and component definitions that contain instances (OD-034).
    static let versionWithLinkedBoxStyles = 5
    /// Version 6 carries instance-owned slot contents, the empty slot state
    /// and slot rules (OD-018).
    static let versionWithSlotContent = 6
    /// Version 7 carries component variants and copies' variant choices (OD-033).
    static let versionWithVariants = 7
    /// Version 8 carries query containers and container-query rules (SF-0605)
    /// and suppressed responsive-audit findings (SF-0606).
    static let versionWithContainerQueries = 8
    static let currentVersion = versionWithContainerQueries

    /// SF-0605: any container name or container-query rule.
    static func carriesContainerQueries(_ nodes: [DocumentNode]) -> Bool {
        nodes.contains { node in node.properties.contains {
            $0.key.rawValue.hasPrefix(CanonicalContainerQueries.namespace)
                || $0.key.rawValue.hasPrefix(CanonicalResponsiveAuditSuppression.namespace)
        } }
    }

    /// OD-033: any variant metadata, override or copy choice.
    static func carriesVariantData(_ nodes: [DocumentNode]) -> Bool {
        nodes.contains { node in node.properties.contains { property in
            property.key.rawValue.hasPrefix(CanonicalComponentVariants.namespace)
                || CanonicalComponentVariants.isChoiceKey(property.key.rawValue)
        } }
    }

    /// OD-018: any instance child, slot marker, slot membership or slot rule.
    static func carriesSlotContent(_ nodes: [DocumentNode]) -> Bool {
        nodes.contains { node in
            (node.kind == .component && !node.childIDs.isEmpty) || node.properties.contains { property in
                let key = property.key.rawValue
                return key.hasPrefix(CanonicalComponentSlot.overrideNamespace) || key == CanonicalComponentSlot.supplyKey
                    || CanonicalComponentSlot.ruleKeys.contains(key)
            }
        }
    }
    static let maximumEncodedBytes = 64 * 1_024 * 1_024
    static let maximumNodes = 10_000
    static let maximumRoots = 1_000
    static let maximumDependencies = 1_000
    static let maximumComponentDefinitions = 256
    static let maximumGraphDepth = 256

    let version: Int
    let sourceDocumentID: DocumentID
    let sourcePageID: PageID
    let roots: [NodeID]
    let nodes: [DocumentNode]
    let imageDependencies: [ClipboardImageDependency]
    let colorTokenDependencies: [LocalColorToken]
    let reusableStyleDependencies: [ClipboardReusableStyleDependency]
    let componentDefinitions: [DocumentPage]

    init(
        version: Int? = nil,
        sourceDocumentID: DocumentID,
        sourcePageID: PageID,
        roots: [NodeID],
        nodes: [DocumentNode],
        imageDependencies: [ClipboardImageDependency] = [],
        colorTokenDependencies: [LocalColorToken] = [],
        reusableStyleDependencies: [ClipboardReusableStyleDependency] = [],
        componentDefinitions: [DocumentPage] = []
    ) {
        let containsUsageNotes = componentDefinitions.contains { definition in
            definition.nodes.contains { $0.properties.contains(where: CanonicalComponentUsageNotes.owns) }
        }
        let usesDecorativeData = colorTokenDependencies.contains { $0.darkColor != nil }
            || (nodes + componentDefinitions.flatMap(\.nodes)).contains { node in node.properties.contains {
                $0.key.rawValue.hasPrefix("style.flow.") || $0.key.rawValue.hasPrefix("style.glass.") || $0.key.rawValue.hasPrefix("content.qr.")
            } }
        // Each format is the oldest reader that keeps everything: variants
        // (OD-033) need v7; slot contents (OD-018) need v6; linked box styles
        // (SF-0510) and nested definitions (OD-034) need v5. Older readers
        // refuse or would drop them.
        let requiresV5 = reusableStyleDependencies.contains { !$0.box.isEmpty }
            || componentDefinitions.contains { $0.nodes.contains { $0.kind == .component } }
        let requiresV6 = Self.carriesSlotContent(nodes + componentDefinitions.flatMap(\.nodes))
        let requiresV7 = Self.carriesVariantData(nodes + componentDefinitions.flatMap(\.nodes))
        let requiresV8 = Self.carriesContainerQueries(nodes + componentDefinitions.flatMap(\.nodes))
        self.version = version ?? (requiresV8 ? Self.versionWithContainerQueries
            : requiresV7 ? Self.versionWithVariants
            : requiresV6 ? Self.versionWithSlotContent
            : requiresV5 ? Self.versionWithLinkedBoxStyles
            : usesDecorativeData ? Self.versionWithDecorativeData
            : containsUsageNotes ? 3 : Self.versionWithoutUsageNotes)
        self.sourceDocumentID = sourceDocumentID
        self.sourcePageID = sourcePageID
        self.roots = roots
        self.nodes = nodes
        self.imageDependencies = imageDependencies
        self.colorTokenDependencies = colorTokenDependencies
        self.reusableStyleDependencies = reusableStyleDependencies
        self.componentDefinitions = componentDefinitions
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, sourceDocumentID, sourcePageID, roots, nodes, imageDependencies,
             colorTokenDependencies, reusableStyleDependencies, componentDefinitions
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        sourceDocumentID = try values.decode(DocumentID.self, forKey: .sourceDocumentID)
        sourcePageID = try values.decode(PageID.self, forKey: .sourcePageID)
        roots = try values.decode([NodeID].self, forKey: .roots)
        nodes = try values.decode([DocumentNode].self, forKey: .nodes)
        imageDependencies = try values.decode([ClipboardImageDependency].self, forKey: .imageDependencies)
        colorTokenDependencies = try values.decode([LocalColorToken].self, forKey: .colorTokenDependencies)
        reusableStyleDependencies = try values.decode([ClipboardReusableStyleDependency].self, forKey: .reusableStyleDependencies)
        componentDefinitions = try values.decode([DocumentPage].self, forKey: .componentDefinitions)
        try validate()
    }

    func validate() throws {
        guard (Self.versionWithoutUsageNotes...Self.currentVersion).contains(version) else {
            throw ClipboardTransferError.unsupportedVersion
        }
        let properties = nodes.flatMap(\.properties)
        guard !roots.isEmpty, roots.count <= Self.maximumRoots,
              Set(roots).count == roots.count,
              !nodes.isEmpty, nodes.count <= Self.maximumNodes,
              Set(nodes.map(\.id)).count == nodes.count,
              Set(properties.map(\.id)).count == properties.count,
              imageDependencies.count + colorTokenDependencies.count + reusableStyleDependencies.count <= Self.maximumDependencies,
              Set(imageDependencies.map { $0.asset.id }).count == imageDependencies.count,
              Set(colorTokenDependencies.map(\.id)).count == colorTokenDependencies.count,
              Set(reusableStyleDependencies.map(\.id)).count == reusableStyleDependencies.count,
              componentDefinitions.count <= Self.maximumComponentDefinitions,
              Set(componentDefinitions.map(\.id)).count == componentDefinitions.count else {
            throw ClipboardTransferError.invalidEnvelope
        }
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        guard roots.allSatisfy({ byID[$0] != nil }) else { throw ClipboardTransferError.invalidEnvelope }
        let rootSet = Set(roots)
        for node in nodes {
            guard Set(node.childIDs).count == node.childIDs.count,
                  node.childIDs.allSatisfy({ byID[$0]?.parent == .node(node.id) }) else {
                throw ClipboardTransferError.invalidEnvelope
            }
            switch node.parent {
            case .page(let page):
                guard page == sourcePageID, rootSet.contains(node.id) else { throw ClipboardTransferError.invalidEnvelope }
            case .node(let parent):
                guard byID[parent]?.childIDs.contains(node.id) == true,
                      !rootSet.contains(node.id) else { throw ClipboardTransferError.invalidEnvelope }
            }
        }
        var reachable = Set<NodeID>()
        var pending = Array(roots.reversed())
        while let id = pending.popLast() {
            guard reachable.insert(id).inserted, let node = byID[id] else {
                throw ClipboardTransferError.invalidEnvelope
            }
            pending.append(contentsOf: node.childIDs.reversed())
        }
        guard reachable.count == nodes.count else { throw ClipboardTransferError.invalidEnvelope }
        for dependency in imageDependencies { try dependency.validate() }
        guard reusableStyleDependencies.allSatisfy(\.isValid) else {
            throw ClipboardTransferError.invalidDependency
        }
        // An older reader would drop linked box values: they require v5.
        if version < Self.versionWithLinkedBoxStyles, reusableStyleDependencies.contains(where: { !$0.box.isEmpty }) {
            throw ClipboardTransferError.unsupportedVersion
        }
        let definitionNodes = componentDefinitions.flatMap(\.nodes)
        // OD-034: nested definitions first appear in v5; earlier writers never
        // produced them, so an older header carrying them is malformed.
        if version < Self.versionWithLinkedBoxStyles, definitionNodes.contains(where: { $0.kind == .component }) {
            throw ClipboardTransferError.unsupportedVersion
        }
        let allNodes = nodes + definitionNodes
        guard !allNodes.contains(where: CanonicalPageFlow.isManaged) else { throw ClipboardTransferError.unsupportedPageStructure }
        // OD-033: variants first appear in v7; older writers never produced them.
        if version < Self.versionWithVariants, Self.carriesVariantData(allNodes) {
            throw ClipboardTransferError.unsupportedVersion
        }
        // SF-0605: container queries first appear in v8.
        if version < Self.versionWithContainerQueries, Self.carriesContainerQueries(allNodes) {
            throw ClipboardTransferError.unsupportedVersion
        }
        // OD-018: slot contents travel with v6 and obey the same structure
        // and rules as in a document (copied definitions supply the rules).
        if Self.carriesSlotContent(allNodes) {
            guard version >= Self.versionWithSlotContent else { throw ClipboardTransferError.unsupportedVersion }
            let slots = CanonicalComponentSlot.slotsByDefinition(componentDefinitions)
            do {
                try CanonicalComponentSlot.validateNodes(nodes, inDefinition: false, slotsByDefinition: slots)
                for definition in componentDefinitions {
                    try CanonicalComponentSlot.validateNodes(definition.nodes, inDefinition: true, slotsByDefinition: slots)
                }
            } catch { throw ClipboardTransferError.unsupportedSlotContent }
        }
        if version < 4, colorTokenDependencies.contains(where: { $0.darkColor != nil }) || allNodes.contains(where: { node in node.properties.contains {
            $0.key.rawValue.hasPrefix("style.flow.") || $0.key.rawValue.hasPrefix("style.glass.") || $0.key.rawValue.hasPrefix("content.qr.")
        } }) { throw ClipboardTransferError.unsupportedVersion }
        let definitionNodeIDs = Set(definitionNodes.map(\.id))
        let definitionRootIDs = Set(componentDefinitions.compactMap { $0.rootNodeIDs.first })
        if version < 3,
           allNodes.contains(where: { $0.properties.contains(where: CanonicalComponentUsageNotes.owns) }) {
            throw ClipboardTransferError.unsupportedVersion
        }
        do {
            for node in allNodes {
                guard Set(node.properties.map(\.key)).count == node.properties.count else {
                    throw ClipboardTransferError.invalidEnvelope
                }
                try CanonicalComponentAction.validate(node, inDefinition: definitionNodeIDs.contains(node.id))
                try CanonicalComponentSlot.validate(node, inDefinition: definitionNodeIDs.contains(node.id))
                try CanonicalComponentOrganization.validate(node, inDefinition: definitionNodeIDs.contains(node.id))
                try CanonicalComponentUsageNotes.validate(node, isDefinitionRoot: definitionRootIDs.contains(node.id))
                try CanonicalLinkTarget.validate(node)
                _ = try CanonicalFlowGradient.resolve(node)
                _ = try CanonicalGlassSurface.resolve(node)
                _ = try CanonicalQRCode.resolve(node)
            }
        } catch { throw ClipboardTransferError.invalidEnvelope }
        let allProperties = allNodes.flatMap(\.properties)
        guard allNodes.count <= Self.maximumNodes else { throw ClipboardTransferError.oversized }
        guard Set(allNodes.map(\.id)).count == allNodes.count,
              Set(allProperties.map(\.id)).count == allProperties.count else {
            throw ClipboardTransferError.invalidEnvelope
        }
        let definitionIDs = Set(componentDefinitions.map(\.id))
        guard componentDefinitions.allSatisfy({ definition in
            definition.role == .componentDefinition && definition.route.rawValue.isEmpty
                && definition.rootNodeIDs.count == 1 && !definition.nodes.isEmpty
        }) else { throw ClipboardTransferError.invalidEnvelope }
        let referencedDefinitions = Set(allNodes.compactMap(CanonicalComponentReference.definitionID))
        guard referencedDefinitions == definitionIDs else {
            throw ClipboardTransferError.invalidDependency
        }
        try Self.validateDefinitionDependencies(componentDefinitions)
        let actionBindings = componentDefinitions.flatMap(CanonicalComponentAction.properties).map(\.id)
        guard Set(actionBindings).count == actionBindings.count else { throw ClipboardTransferError.invalidDependency }
        // OD-034: definitions may contain instances of other carried
        // definitions; the dependency check above keeps them acyclic and
        // closed, and the destination document validation bounds depth/size.
        guard CanonicalComponentGraph(definitions: componentDefinitions).violation == nil else {
            throw ClipboardTransferError.componentCycle
        }
        // The same references copying collects (translated images included).
        let referencedAssets = Set(allNodes.flatMap(CanonicalGraphReferences.assets))
        let referencedTokens = Set(allNodes.flatMap { node in
            LocalColorTarget.allCases.compactMap { LocalColorTokenBinding.id(for: node, target: $0) }
        })
        let referencedStyles = Set(try allNodes.flatMap(CanonicalReusableStyleIndex.strictlyDecodedAppliedIDs))
        guard referencedAssets == Set(imageDependencies.map { $0.asset.id }),
              referencedTokens == Set(colorTokenDependencies.map(\.id)),
              referencedStyles == Set(reusableStyleDependencies.map(\.id)),
              colorTokenDependencies.allSatisfy(\.isValid) else {
            throw ClipboardTransferError.invalidDependency
        }
        for definition in componentDefinitions {
            try Self.validateDefinitionGraph(definition)
        }
    }

    private static func validateDefinitionGraph(_ definition: DocumentPage) throws {
        do { try CanonicalComponentSlot.validateDefinition(definition) }
        catch { throw ClipboardTransferError.unsupportedSlotContent }
        do { try CanonicalComponentOrganization.validateDefinition(definition) }
        catch { throw ClipboardTransferError.invalidEnvelope }
        let byID = Dictionary(uniqueKeysWithValues: definition.nodes.map { ($0.id, $0) })
        guard byID.count == definition.nodes.count,
              Set(definition.nodes.flatMap(\.properties).map(\.id)).count == definition.nodes.flatMap(\.properties).count,
              let root = definition.rootNodeIDs.first, byID[root]?.parent == .page(definition.id) else {
            throw ClipboardTransferError.invalidEnvelope
        }
        var visited = Set<NodeID>(), pending: [(NodeID, Int)] = [(root, 1)]
        while let (id, depth) = pending.popLast() {
            guard depth <= maximumGraphDepth else { throw ClipboardTransferError.oversized }
            guard visited.insert(id).inserted, let node = byID[id],
                  Set(node.childIDs).count == node.childIDs.count,
                  node.childIDs.allSatisfy({ byID[$0]?.parent == .node(id) }) else {
                throw ClipboardTransferError.invalidEnvelope
            }
            pending.append(contentsOf: node.childIDs.map { ($0, depth + 1) })
        }
        guard visited.count == definition.nodes.count else { throw ClipboardTransferError.invalidEnvelope }
    }

    private static func validateDefinitionDependencies(_ definitions: [DocumentPage]) throws {
        let known = Set(definitions.map(\.id))
        let dependencies = Dictionary(uniqueKeysWithValues: definitions.map { definition in
            (definition.id, Set(definition.nodes.compactMap(CanonicalComponentReference.definitionID)))
        })
        guard dependencies.values.allSatisfy({ $0.isSubset(of: known) }) else {
            throw ClipboardTransferError.invalidDependency
        }
        enum Visit { case visiting, visited }
        var state: [PageID: Visit] = [:]
        for start in definitions.map(\.id) where state[start] == nil {
            var stack: [(PageID, Bool)] = [(start, false)]
            while let (id, exiting) = stack.popLast() {
                if exiting { state[id] = .visited; continue }
                if state[id] == .visiting { throw ClipboardTransferError.componentCycle }
                if state[id] == .visited { continue }
                state[id] = .visiting
                stack.append((id, true))
                for dependency in dependencies[id, default: []].sorted(by: { $0.description > $1.description }) {
                    if state[dependency] == .visiting { throw ClipboardTransferError.componentCycle }
                    if state[dependency] != .visited { stack.append((dependency, false)) }
                }
            }
        }
    }
}

struct ClipboardReusableStyleDependency: Codable, Equatable, Sendable {
    let id: ReusableStyleID
    let name: String
    let fill: CanonicalSolidColor?
    let opacity: Double?
    /// SF-0510 (clipboard v5): linked border, corner radius and shadow, in the
    /// same field codec the document uses. Omitted when empty.
    let box: CanonicalReusableBoxAppearance

    init(id: ReusableStyleID, name: String, fill: CanonicalSolidColor?, opacity: Double?,
         box: CanonicalReusableBoxAppearance = .init()) {
        self.id = id; self.name = name; self.fill = fill; self.opacity = opacity; self.box = box
    }

    var isValid: Bool {
        CanonicalReusableStyleIndex.validName(name) && (fill?.isValid ?? true)
            && (opacity.map { $0.isFinite && (0...1).contains($0) } ?? true)
            && box.isValid && box == box.quantized
            && (fill != nil || opacity != nil || !box.isEmpty)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, name, fill, opacity, box }

    init(from decoder: Decoder) throws {
        try requireKnownKeys(CodingKeys.self, in: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(ReusableStyleID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        fill = try values.decodeIfPresent(CanonicalSolidColor.self, forKey: .fill)
        opacity = try values.decodeIfPresent(Double.self, forKey: .opacity)
        if let fields = try values.decodeIfPresent([String: PropertyValue].self, forKey: .box) {
            // An explicit empty box is not a canonical encoding.
            guard !fields.isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .box, in: values,
                    debugDescription: "Omit an empty linked box appearance.")
            }
            do { box = try CanonicalReusableBoxAppearance.decode(fields) } catch {
                throw DecodingError.dataCorruptedError(forKey: .box, in: values,
                    debugDescription: "Invalid linked box appearance.")
            }
        } else {
            box = .init()
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encodeIfPresent(fill, forKey: .fill)
        try values.encodeIfPresent(opacity, forKey: .opacity)
        if !box.isEmpty {
            try values.encode(Dictionary(uniqueKeysWithValues: box.fieldValues.map { ($0.field, $0.value) }), forKey: .box)
        }
    }
}

struct ClipboardImageDependency: Codable, Equatable, Sendable {
    let asset: ImageAsset
    let descriptor: ProjectResourceDescriptor
    let bytes: Data

    func validate() throws {
        try asset.validate()
        try ProjectResourceIndex(resources: [descriptor]).validate()
        guard descriptor.id == asset.resourceID,
              descriptor.sha256 == asset.contentHash,
              descriptor.byteCount == bytes.count,
              ProjectResourceStore.digest(bytes) == descriptor.sha256 else {
            throw ClipboardTransferError.invalidDependency
        }
    }
}

enum ClipboardPastePlacement: String, Codable, Sendable {
    case offset
    case inPlace
}

enum ClipboardOperationProvenance: String, Sendable {
    case keyboard, menu, contextualMenu, accessibility, automation
}

struct ClipboardOperationIdentity: Equatable, Sendable {
    let documentID: DocumentID
    let pageID: PageID
    let revision: UInt64
    let sceneID: CanvasViewportSceneID
    let rendererGeneration: UInt64
    let selectedNodeIDs: [NodeID]
}

struct ClipboardValidationContext: Equatable, Sendable {
    let liveIdentity: ClipboardOperationIdentity
    let activeContainerID: NodeID?
    let lifecycleAvailable: Bool
    let disabledReason: String?
    /// OD-018: when set, `activeContainerID` is a component copy and the
    /// pasted objects become top-level items of this slot of that copy.
    var slotID: ComponentSlotPropertyID? = nil
}

struct PreparedClipboardTransfer: Sendable {
    let documentID: DocumentID
    let revision: UInt64
    let command: DocumentCommand
    let insertedRootIDs: [NodeID]
    let resources: [ClipboardImageDependency]
    let skippedDependencies: [String]
    let componentSummary: ClipboardComponentTransferSummary?
}

struct ClipboardComponentTransferSummary: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        enum Resolution: String, Sendable { case imported, reused, renamed }
        let sourceDefinitionID: PageID
        let destinationDefinitionID: PageID
        let displayName: String
        let resolution: Resolution
    }
    let entries: [Entry]

    var accessibilitySummary: String {
        let imported = entries.filter { $0.resolution == .imported }.count
        let reused = entries.filter { $0.resolution == .reused }.count
        let renamed = entries.filter { $0.resolution == .renamed }.count
        return "Component transfer: \(imported) imported, \(reused) reused, \(renamed) renamed."
    }
}

private struct ClipboardComponentImportPlan {
    let definitionMap: [PageID: PageID]
    let definitionNameMap: [PageID: String]
    let textPropertyMap: [ComponentTextPropertyID: ComponentTextPropertyID]
    let visibilityPropertyMap: [ComponentVisibilityPropertyID: ComponentVisibilityPropertyID]
    let choicePropertyMap: [ComponentChoicePropertyID: ComponentChoicePropertyID]
    let mediaPropertyMap: [ComponentMediaPropertyID: ComponentMediaPropertyID]
    let actionPropertyMap: [ComponentActionPropertyID: ComponentActionPropertyID]
    let definitionNodeMap: [NodeID: NodeID]
    let importedDefinitions: [DocumentPage]
    let summary: ClipboardComponentTransferSummary?
    /// OD-018: carried slot identities → destination slot identities.
    var slotPropertyMap: [ComponentSlotPropertyID: ComponentSlotPropertyID] = [:]
}

enum ClipboardTransferError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case unavailable(String)
    case stale
    case emptySelection
    case invalidSelection
    case invalidTarget
    case unsupportedVersion
    case oversized
    case invalidEnvelope
    case invalidDependency
    case unsupportedComponentDependency
    case unmappedActionDestination
    case unsupportedSlotContent
    case unresolvedComponentOverride
    case unsupportedPageStructure
    case componentCycle
    /// OD-034: the paste would place a component inside itself or past the
    /// nesting limits of the definition being edited.
    case componentNesting(ComponentGraphViolation)
    case clipboardUnavailable

    var errorDescription: String? {
        switch self {
        case .cancelled: "Clipboard operation cancelled; the document is unchanged."
        case .unavailable(let reason): reason
        case .stale: "The document or rendered selection changed. Copy again and retry."
        case .emptySelection: "Select one or more authored objects first."
        case .invalidSelection: "The selected objects no longer form a transferable authored subtree."
        case .invalidTarget: "Choose a page or container that can accept the transferred objects."
        case .unsupportedVersion: "This SiteForge clipboard format is not supported. Copy the objects again."
        case .oversized: "The selection exceeds the bounded clipboard transfer limit. Copy fewer objects."
        case .invalidEnvelope: "The clipboard data is malformed or incomplete. Copy the objects again."
        case .invalidDependency: "A required local dependency is missing or corrupt. Reimport it and copy again."
        case .unsupportedComponentDependency: "This component contains a dependency that cannot be transferred safely. Remove the unsupported construct or detach the instance."
        case .unmappedActionDestination: "An action destination is outside this transfer. Copy its target section with the instance, or reset/change the destination before pasting into another project. No content was changed."
        case .unsupportedSlotContent: "The copied slot contents are incomplete or break the slot's rules. Copy them again from SiteForge. Nothing was changed."
        case .unresolvedComponentOverride: "An original component definition or retained override is unresolved. Inspect/restore the original definition or explicitly reset retained conflicts before transferring. Nothing was changed."
        case .unsupportedPageStructure: "Connected page structure and navigation cannot be transferred as isolated objects in this version. Duplicate the complete page or recreate the structure at the destination. Nothing was changed."
        case .componentCycle: "The component dependency graph contains a cycle. Repair the component definitions before copying."
        case .componentNesting(let violation): (violation.errorDescription ?? "") + " Nothing was pasted."
        case .clipboardUnavailable: "The macOS clipboard could not accept or provide SiteForge objects. Try Copy again."
        }
    }

    var diagnosticCategory: String {
        switch self {
        case .cancelled: "cancelled"
        case .unavailable: "unavailable"
        case .stale: "stale-identity"
        case .emptySelection: "empty-selection"
        case .invalidSelection: "invalid-selection"
        case .invalidTarget: "invalid-target"
        case .unsupportedVersion: "unsupported-version"
        case .oversized: "capacity-limit"
        case .invalidEnvelope: "invalid-envelope"
        case .invalidDependency: "invalid-dependency"
        case .unsupportedComponentDependency: "unsupported-component-dependency"
        case .unmappedActionDestination: "unmapped-action-destination"
        case .unsupportedSlotContent: "unsupported-slot-content"
        case .unresolvedComponentOverride: "component-override-conflict"
        case .unsupportedPageStructure: "unsupported-page-structure"
        case .componentCycle: "component-cycle"
        case .componentNesting(let violation): violation.category
        case .clipboardUnavailable: "clipboard-unavailable"
        }
    }
}

enum SiteForgeClipboardCodec {
    static func encode(_ value: SiteForgeClipboardEnvelope) throws -> Data {
        try value.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard data.count <= SiteForgeClipboardEnvelope.maximumEncodedBytes else { throw ClipboardTransferError.oversized }
        return data
    }

    static func decode(_ data: Data) throws -> SiteForgeClipboardEnvelope {
        guard !data.isEmpty, data.count <= SiteForgeClipboardEnvelope.maximumEncodedBytes else {
            throw ClipboardTransferError.oversized
        }
        do { return try JSONDecoder().decode(SiteForgeClipboardEnvelope.self, from: data) }
        catch let error as ClipboardTransferError { throw error }
        catch { throw ClipboardTransferError.invalidEnvelope }
    }
}

struct ClipboardTransferRegistry {
    static let requirementIDs: Set<String> = [
        "SF-0308-001", "SF-0308-002", "SF-0308-003", "SF-0308-004",
        "SF-0308-005", "SF-0308-006", "SF-0308-007", "SF-0308-008",
    ]

    /// The pasted objects that arrive in world positions: the roots and their
    /// descendants, but not a pasted copy's own slot contents, which stay
    /// slot-local to that copy (OD-018).
    static func worldPositionedNodeIDs(_ nodes: [DocumentNode], roots: Set<NodeID>) -> Set<NodeID> {
        let byID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Prepared paste nodes intentionally have empty childIDs until their
        // insertion commands run. Parent references already describe the tree.
        let children = Dictionary(grouping: nodes.compactMap { node -> (NodeID, NodeID)? in
            guard case .node(let parent) = node.parent else { return nil }
            return (parent, node.id)
        }, by: { $0.0 })
        var result = Set<NodeID>()
        var pending = Array(roots)
        while let id = pending.popLast() {
            guard let node = byID[id], result.insert(id).inserted else { continue }
            if node.kind != .component { pending += children[id, default: []].map { $0.1 } }
        }
        return result
    }

    /// Definition-owned metadata, never instance values (OD-034 copy rule).
    static let definitionOwnedPrefixes = [
        CanonicalComponentText.namespace, CanonicalComponentVisibility.namespace, CanonicalComponentChoice.namespace,
        CanonicalComponentMedia.namespace, CanonicalComponentAction.namespace, CanonicalComponentSlot.namespace,
        CanonicalComponentOrganization.namespace, CanonicalComponentVariants.namespace,
    ]

    func prepareCopy(
        identity: ClipboardOperationIdentity,
        document: CanonicalDocument,
        resourceData: (ResourceID) throws -> (ProjectResourceDescriptor, Data),
        cancelled: Bool = false
    ) throws -> SiteForgeClipboardEnvelope {
        guard !cancelled else { throw ClipboardTransferError.cancelled }
        guard identity.documentID == document.id, identity.revision == document.revision,
              let page = document.pages.first(where: { $0.id == identity.pageID }) else {
            throw ClipboardTransferError.stale
        }
        guard !identity.selectedNodeIDs.isEmpty else { throw ClipboardTransferError.emptySelection }
        let selected = Set(identity.selectedNodeIDs)
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        guard selected.count == identity.selectedNodeIDs.count,
              selected.allSatisfy({ byID[$0] != nil }) else { throw ClipboardTransferError.invalidSelection }

        let roots = identity.selectedNodeIDs.filter { id in
            guard let node = byID[id] else { return false }
            if case .node(let parent) = node.parent { return !hasSelectedAncestor(parent, selected: selected, nodes: byID) }
            return true
        }
        guard roots.allSatisfy({ !page.rootNodeIDs.contains($0) }) else {
            throw ClipboardTransferError.invalidSelection
        }
        var ordered: [DocumentNode] = []
        var visited = Set<NodeID>()
        var pending = Array(roots.reversed())
        while let id = pending.popLast() {
            guard visited.insert(id).inserted, let node = byID[id] else { throw ClipboardTransferError.invalidSelection }
            ordered.append(node)
            pending.append(contentsOf: node.childIDs.reversed())
        }
        guard ordered.count <= SiteForgeClipboardEnvelope.maximumNodes else { throw ClipboardTransferError.oversized }
        // OD-018: content copied from a copy's slot is carried in world
        // coordinates (as the canvas shows it) without slot membership, so it
        // pastes anywhere; pasting into slot contents converts it back.
        // A copy that comes along with its owning instance keeps its slot
        // storage (the instance travels too).
        let slotOffsets = CanonicalSlotGeometry.offsetsByBreakpoint(in: page, document: document)
        if !slotOffsets.isEmpty {
            let zero = WorldVector(dx: 0, dy: 0)
            let copied = Set(ordered.map(\.id))
            func ownerIsCopied(_ node: DocumentNode) -> Bool {
                var parent = node.parent
                while case .node(let id) = parent, let ancestor = byID[id] {
                    if ancestor.kind == .component { return copied.contains(id) }
                    parent = ancestor.parent
                }
                return false
            }
            ordered = ordered.map { node in
                guard slotOffsets[.desktop]?[node.id] != nil, !ownerIsCopied(node) else { return node }
                var copy = CanonicalSlotGeometry.shifted(node, sign: 1) { slotOffsets[$0]?[node.id] ?? zero }
                copy.properties.removeAll { $0.key.rawValue == CanonicalComponentSlot.supplyKey }
                return copy
            }
        }
        if page.role == .componentDefinition {
            // OD-034: a copy taken inside a definition is ordinary content.
            // The definition keeps its exposed properties, slots, organization
            // and notes; the copy carries their current values only.
            ordered = ordered.map { node in
                var copy = node
                copy.properties.removeAll { property in
                    Self.definitionOwnedPrefixes.contains { property.key.rawValue.hasPrefix($0) }
                        || CanonicalComponentUsageNotes.owns(property)
                }
                return copy
            }
        }
        guard !ordered.contains(where: CanonicalPageFlow.isManaged) else { throw ClipboardTransferError.unsupportedPageStructure }
        for instance in ordered where instance.kind == .component {
            guard try !CanonicalComponentOverrides.requiresRecovery(instance: instance, document: document) else {
                throw ClipboardTransferError.unresolvedComponentOverride
            }
        }

        let definitionsByID = Dictionary(uniqueKeysWithValues: document.componentDefinitions.map { ($0.id, $0) })
        var componentDefinitions: [DocumentPage] = []
        var visitedDefinitions = Set<PageID>()
        var pendingDefinitions = Array(ordered.compactMap(CanonicalComponentReference.definitionID).reversed())
        while let definitionID = pendingDefinitions.popLast() {
            guard visitedDefinitions.insert(definitionID).inserted else { continue }
            guard let definition = definitionsByID[definitionID] else {
                throw ClipboardTransferError.invalidDependency
            }
            componentDefinitions.append(definition)
            pendingDefinitions.append(contentsOf: definition.nodes.compactMap(CanonicalComponentReference.definitionID).reversed())
            guard componentDefinitions.count <= SiteForgeClipboardEnvelope.maximumComponentDefinitions else {
                throw ClipboardTransferError.oversized
            }
        }
        let dependencyNodes = ordered + componentDefinitions.flatMap(\.nodes)
        let assetIDs = Set(dependencyNodes.flatMap(Self.assetReferences))
        let assetsByID = Dictionary(uniqueKeysWithValues: document.imageAssets.map { ($0.id, $0) })
        let imageDependencies = try assetIDs.sorted { $0.description < $1.description }.map { id -> ClipboardImageDependency in
            guard let asset = assetsByID[id] else { throw ClipboardTransferError.invalidDependency }
            let (descriptor, bytes) = try resourceData(asset.resourceID)
            return .init(asset: asset, descriptor: descriptor, bytes: bytes)
        }
        let tokenIDs = Set(dependencyNodes.flatMap(Self.tokenReferences))
        let tokensByID = Dictionary(uniqueKeysWithValues: document.colorTokens.map { ($0.id, $0) })
        let tokens = try tokenIDs.sorted { $0.description < $1.description }.map {
            guard let token = tokensByID[$0] else { throw ClipboardTransferError.invalidDependency }
            return token
        }
        let styleIndex = try CanonicalReusableStyleIndex(document: document)
        let styleIDs = Set(try dependencyNodes.flatMap(CanonicalReusableStyleIndex.strictlyDecodedAppliedIDs))
        let styles = try styleIDs.sorted { $0.description < $1.description }.map { id -> ClipboardReusableStyleDependency in
            guard let style = styleIndex.byID[id] else { throw ClipboardTransferError.invalidDependency }
            return .init(id: style.id, name: style.name, fill: style.fill, opacity: style.opacity, box: style.box)
        }
        let rootSet = Set(roots)
        let transferableNodes = ordered.map { node -> DocumentNode in
            guard rootSet.contains(node.id) else { return node }
            var copy = node
            copy.parent = .page(page.id)
            return copy
        }
        let envelope = SiteForgeClipboardEnvelope(
            sourceDocumentID: document.id, sourcePageID: page.id, roots: roots,
            nodes: transferableNodes, imageDependencies: imageDependencies, colorTokenDependencies: tokens,
            reusableStyleDependencies: styles, componentDefinitions: componentDefinitions
        )
        try envelope.validate()
        return envelope
    }

    func preparePaste(
        envelope: SiteForgeClipboardEnvelope,
        identity: ClipboardOperationIdentity,
        document: CanonicalDocument,
        context: ClipboardValidationContext,
        placement: ClipboardPastePlacement,
        cancelled: Bool = false
    ) throws -> PreparedClipboardTransfer {
        guard !cancelled else { throw ClipboardTransferError.cancelled }
        guard context.lifecycleAvailable else {
            throw ClipboardTransferError.unavailable(context.disabledReason ?? "Clipboard editing is unavailable.")
        }
        guard identity == context.liveIdentity, identity.documentID == document.id,
              identity.revision == document.revision,
              let pageIndex = document.pages.firstIndex(where: { $0.id == identity.pageID }) else {
            throw ClipboardTransferError.stale
        }
        try envelope.validate()
        let isCrossProject = envelope.sourceDocumentID != document.id
        for instance in envelope.nodes where instance.kind == .component {
            if !isCrossProject, try CanonicalComponentOverrides.requiresRecovery(instance: instance, document: document) {
                throw ClipboardTransferError.unresolvedComponentOverride
            }
            let conflicts = try CanonicalComponentOverrides.conflicts(instance: instance, document: document,
                definitions: envelope.componentDefinitions)
            guard !conflicts.contains(where: { $0.reason == .missingDefinition || $0.reason == .missingProperty }) else {
                throw ClipboardTransferError.unresolvedComponentOverride
            }
        }
        if isCrossProject {
            let copiedIDs = Set(envelope.nodes.map(\.id))
            for property in envelope.nodes.flatMap(\.properties) {
                let key = property.key.rawValue
                if key == CanonicalLinkTarget.namespace + "nodeID",
                   case .string(let raw) = property.value,
                   let target = NodeID(uuidString: raw), !copiedIDs.contains(target) {
                    throw ClipboardTransferError.invalidDependency
                }
                if key == CanonicalLinkTarget.namespace + "pageID",
                   case .string(let raw) = property.value,
                   let target = PageID(uuidString: raw), target != envelope.sourcePageID {
                    throw ClipboardTransferError.invalidDependency
                }
            }
            let allNodes = envelope.nodes + envelope.componentDefinitions.flatMap(\.nodes)
            let byID = Dictionary(uniqueKeysWithValues: allNodes.map { ($0.id, $0) })
            let owningPage = Dictionary(uniqueKeysWithValues:
                envelope.nodes.map { ($0.id, envelope.sourcePageID) } + envelope.componentDefinitions.flatMap { definition in
                    definition.nodes.map { ($0.id, definition.id) }
                })
            for node in allNodes {
                var targets = Array(CanonicalComponentAction.overrides(on: node).values)
                if node.kind.isLinkControl { targets.append(try CanonicalLinkTarget.resolve(node)) }
                for target in targets {
                    if case .section(let pageID, let targetID) = target {
                        guard byID[targetID]?.kind == .section, owningPage[targetID] == pageID else {
                            throw ClipboardTransferError.unmappedActionDestination
                        }
                    }
                }
            }
        }
        let page = document.pages[pageIndex]
        let destination: NodeParent
        let insertionIndex: Int
        guard let containerID = context.activeContainerID,
              let container = page.nodes.first(where: { $0.id == containerID }),
              container.kind.acceptsAuthoredChildren || (context.slotID != nil && container.kind == .component),
              !container.selectionBooleanProperty("locked"),
              !container.selectionBooleanProperty("hidden") else {
            throw ClipboardTransferError.invalidTarget
        }
        destination = .node(containerID)
        // OD-018: a slot target appends after the slot's last top-level item.
        var slotTarget: (slot: ExposedComponentSlotProperty, existing: [DocumentNode], marker: NodeProperty?)?
        if let slotID = context.slotID {
            guard container.kind == .component,
                  let definitionID = CanonicalComponentReference.definitionID(for: container),
                  let definition = document.componentDefinitions.first(where: { $0.id == definitionID }),
                  let slot = CanonicalComponentSlot.properties(in: definition).first(where: { $0.id == slotID }) else {
                throw ClipboardTransferError.invalidTarget
            }
            let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
            guard CanonicalComponentSlot.state(of: slotID, on: container, nodesByID: byID) != .inherited else {
                throw ClipboardTransferError.unavailable("This copy uses the slot's default contents. Choose Customize or Make Empty first. Nothing was pasted.")
            }
            let existing = CanonicalComponentSlot.suppliedRoots(of: container, nodesByID: byID)[slotID] ?? []
            slotTarget = (slot, existing, CanonicalComponentSlot.markers(on: container)[slotID])
            insertionIndex = container.childIDs.lastIndex { id in existing.contains { $0.id == id } }.map { $0 + 1 }
                ?? container.childIDs.count
        } else {
            insertionIndex = container.childIDs.count
        }

        var assetMap: [AssetID: AssetID] = [:]
        var resourceDependencies: [ClipboardImageDependency] = []
        var assetCommands: [DocumentCommand] = []
        for dependency in envelope.imageDependencies {
            try dependency.validate()
            if let existing = document.imageAssets.first(where: { $0.contentHash == dependency.asset.contentHash }) {
                assetMap[dependency.asset.id] = existing.id
            } else {
                let assetID = AssetID(), resourceID = ResourceID()
                let source = dependency.asset
                let asset = ImageAsset(
                    id: assetID, resourceID: resourceID,
                    displayName: source.displayName, originalFilename: source.originalFilename,
                    format: source.format, pixelWidth: source.pixelWidth, pixelHeight: source.pixelHeight,
                    byteCount: source.byteCount, contentHash: source.contentHash,
                    provenance: source.provenance, organization: source.organization
                )
                let descriptor = ProjectResourceDescriptor(
                    id: resourceID, filename: dependency.descriptor.filename,
                    mediaType: dependency.descriptor.mediaType, byteCount: dependency.bytes.count,
                    sha256: ProjectResourceStore.digest(dependency.bytes)
                )
                assetMap[dependency.asset.id] = assetID
                resourceDependencies.append(.init(asset: asset, descriptor: descriptor, bytes: dependency.bytes))
                assetCommands.append(.insertImageAsset(.init(
                    asset: asset, index: document.imageAssets.count + assetCommands.count
                )))
            }
        }

        var tokenMap: [ColorTokenID: ColorTokenID] = [:]
        var resultingTokens = document.colorTokens
        for token in envelope.colorTokenDependencies {
            if let existing = resultingTokens.first(where: { $0.name == token.name && $0.color == token.color && $0.darkColor == token.darkColor }) {
                tokenMap[token.id] = existing.id
            } else {
                let newID = ColorTokenID()
                let base = token.name
                var name = base, suffix = 2
                let existingNames = Set(resultingTokens.map { $0.name.lowercased() })
                while existingNames.contains(name.lowercased()) {
                    name = String(base.prefix(112)) + " Copy \(suffix)"; suffix += 1
                }
                tokenMap[token.id] = newID
                resultingTokens.append(.init(id: newID, name: name, color: token.color, darkColor: token.darkColor))
            }
        }

        let destinationStyleIndex = try CanonicalReusableStyleIndex(document: document)
        var styleMap: [ReusableStyleID: ReusableStyleID] = [:]
        var importedStyles: [ClipboardReusableStyleDependency] = []
        var reservedStyleNames = Set(destinationStyleIndex.orderedDefinitions.map { $0.name.lowercased() })
        for style in envelope.reusableStyleDependencies {
            guard style.isValid else { throw ClipboardTransferError.invalidDependency }
            if let existing = destinationStyleIndex.orderedDefinitions.first(where: {
                $0.name == style.name && $0.fill == style.fill && $0.opacity == style.opacity && $0.box == style.box
            }) {
                styleMap[style.id] = existing.id
            } else {
                let id = ReusableStyleID()
                var name = style.name, suffix = 2
                while reservedStyleNames.contains(name.lowercased()) {
                    name = String(style.name.prefix(112)) + " Copy \(suffix)"; suffix += 1
                }
                reservedStyleNames.insert(name.lowercased())
                styleMap[style.id] = id
                importedStyles.append(.init(id: id, name: name, fill: style.fill, opacity: style.opacity, box: style.box))
            }
        }

        let nodeMap = Dictionary(uniqueKeysWithValues: envelope.nodes.map { ($0.id, NodeID()) })
        let pageReferenceMap = isCrossProject ? [envelope.sourcePageID: page.id] : [:]
        // Cross-project transfer owns only the selected graph, not a website
        // page import. A source-page mapping is contextual and explicit.
        let componentPlan = try Self.prepareComponentImport(
            envelope: envelope, document: document, isCrossProject: isCrossProject,
            assetMap: assetMap, tokenMap: tokenMap, styleMap: styleMap,
            pageReferenceMap: pageReferenceMap, nodeReferenceMap: nodeMap
        )

        let sourceIDByNodeID = Dictionary(uniqueKeysWithValues: nodeMap.map { ($0.value, $0.key) })
        let propertyMap = Dictionary(uniqueKeysWithValues: envelope.nodes.flatMap(\.properties).map { ($0.id, PropertyID()) })
        let rootSet = Set(envelope.roots)
        var translated = try envelope.nodes.map { source -> DocumentNode in
            guard let nodeID = nodeMap[source.id] else { throw ClipboardTransferError.invalidEnvelope }
            let parent: NodeParent
            if rootSet.contains(source.id) { parent = destination }
            else if case .node(let oldParent) = source.parent, let newParent = nodeMap[oldParent] { parent = .node(newParent) }
            else { throw ClipboardTransferError.invalidEnvelope }
            // OD-045 / SF-0803: playback whose file this project lacks is dropped.
            let properties = try CanonicalMediaPlayback.keepingAvailable(source.properties,
                mediaIDs: Set(document.mediaAssets.map(\.id))).map { property in
                guard let propertyID = propertyMap[property.id] else {
                    throw ClipboardTransferError.invalidEnvelope
                }
                var value = property.value
                let key = property.key.rawValue
                if [CanonicalImageStyle.namespace + "assetID", CanonicalImageFill.assetKey].contains(key)
                    || SiteTranslationKey(rawValue: key)?.field == .imageAssetID,
                   case .string(let raw) = value, let old = AssetID(uuidString: raw), let mapped = assetMap[old] {
                    value = .string(mapped.description)
                } else if key.hasPrefix(LocalColorTokenBinding.prefix), case .string(let raw) = value,
                          let old = ColorTokenID(uuidString: raw), let mapped = tokenMap[old] {
                    value = .string(mapped.description)
                } else if key == CanonicalReusableStyleIndex.appliedKey, case .string(let raw) = value {
                    let remapped = try raw.split(separator: ",", omittingEmptySubsequences: false).map { part -> String in
                        guard let old = ReusableStyleID(uuidString: String(part)), let mapped = styleMap[old] else {
                            throw ClipboardTransferError.invalidDependency
                        }
                        return mapped.description
                    }
                    value = .string(remapped.joined(separator: ","))
                } else if key == CanonicalComponentReference.key, case .string(let raw) = value,
                          let old = PageID(uuidString: raw), let mapped = componentPlan.definitionMap[old] {
                    value = .string(mapped.description)
                } else if let old = CanonicalComponentSlot.overrideID(key) {
                    // OD-018: slot state and membership follow the destination slot.
                    guard let mapped = componentPlan.slotPropertyMap[old] else { throw ClipboardTransferError.invalidDependency }
                    return NodeProperty(id: propertyID, key: .init(rawValue: CanonicalComponentSlot.overrideKey(mapped)),
                                        value: value, origin: property.origin)
                } else if key == CanonicalComponentSlot.supplyKey, case .string(let raw) = value,
                          let old = ComponentSlotPropertyID(uuidString: raw) {
                    guard let mapped = componentPlan.slotPropertyMap[old] else { throw ClipboardTransferError.invalidDependency }
                    value = .string(mapped.description)
                } else if let old = CanonicalComponentText.overrideID(key) {
                    guard let mapped = componentPlan.textPropertyMap[old] else {
                        throw ClipboardTransferError.invalidDependency
                    }
                    value = property.value
                    return NodeProperty(id: propertyID,
                        key: .init(rawValue: CanonicalComponentText.overrideKey(mapped)),
                        value: value, origin: property.origin)
                } else if let old = CanonicalComponentVisibility.overrideID(key) {
                    guard let mapped = componentPlan.visibilityPropertyMap[old] else {
                        throw ClipboardTransferError.invalidDependency
                    }
                    value = property.value
                    return NodeProperty(id: propertyID,
                        key: .init(rawValue: CanonicalComponentVisibility.overrideKey(mapped)),
                        value: value, origin: property.origin)
                } else if let old = CanonicalComponentChoice.overrideID(key) {
                    guard let mapped = componentPlan.choicePropertyMap[old] else {
                        throw ClipboardTransferError.invalidDependency
                    }
                    return NodeProperty(id: propertyID,
                        key: .init(rawValue: CanonicalComponentChoice.overrideKey(mapped)),
                        value: value, origin: property.origin)
                } else if let old = CanonicalComponentMedia.overrideID(key) {
                    guard let mapped = componentPlan.mediaPropertyMap[old], case .string(let raw) = value,
                          let oldAsset = AssetID(uuidString: raw), let newAsset = assetMap[oldAsset] else {
                        throw ClipboardTransferError.invalidDependency
                    }
                    return NodeProperty(id: propertyID,
                        key: .init(rawValue: CanonicalComponentMedia.overrideKey(mapped)),
                        value: .string(newAsset.description), origin: property.origin)
                } else if let old = CanonicalComponentAction.overrideID(key) {
                    guard let mapped = componentPlan.actionPropertyMap[old], case .string(let raw) = value,
                          let target = CanonicalComponentAction.decode(raw) else { throw ClipboardTransferError.invalidDependency }
                    let resolved = try Self.transferredActionTarget(target, isCrossProject: isCrossProject,
                        pageMap: pageReferenceMap.merging(componentPlan.definitionMap, uniquingKeysWith: { first, _ in first }),
                        nodeMap: nodeMap.merging(componentPlan.definitionNodeMap, uniquingKeysWith: { first, _ in first }), sourcePageID: envelope.sourcePageID,
                        destinationPageID: page.id)
                    return NodeProperty(id: propertyID,
                        key: .init(rawValue: CanonicalComponentAction.overrideKey(mapped)),
                        value: .string(CanonicalComponentAction.encode(resolved)), origin: property.origin)
                } else if CanonicalPageChrome.referenceKeys.contains(key), case .string(let raw) = value,
                          let old = NodeID(uuidString: raw), let mapped = nodeMap[old] {
                    value = .string(mapped.description)
                } else if key == CanonicalLinkTarget.namespace + "nodeID", case .string(let raw) = value,
                          let old = NodeID(uuidString: raw), let mapped = nodeMap[old] {
                    value = .string(mapped.description)
                } else if key == CanonicalLinkTarget.namespace + "pageID", case .string(let raw) = value,
                          let old = PageID(uuidString: raw), old == envelope.sourcePageID {
                    value = .string(page.id.description)
                } else if key == CanonicalFormField.optionsKey, case .string(let encoded) = value {
                    value = .string(try CanonicalFormSelectOptions.remappingStableIDs(in: encoded))
                } else if key.hasPrefix(CanonicalFluidValueCodec.namespace + "."), case .string(let encoded) = value,
                          let target = FluidValueTarget(rawValue: String(key.dropFirst(CanonicalFluidValueCodec.namespace.count + 1))) {
                    value = .string(try CanonicalFluidValueCodec.remappingStableID(in: encoded, target: target))
                } else if key == CanonicalEventGraph.interactionsKey {
                    value = CanonicalEventGraph.remappingTargets(value, nodeMap: nodeMap, pageMap: pageReferenceMap)
                }
                if rootSet.contains(source.id), placement == .offset,
                   [GeometryInspectorField.x.propertyKey, GeometryInspectorField.y.propertyKey].contains(key),
                   case .number(let number) = value { value = .number(number + 20) }
                return NodeProperty(id: propertyID, key: property.key, value: value, origin: property.origin)
            }
            let name = CanonicalComponentReference.definitionID(for: source)
                .flatMap { componentPlan.definitionNameMap[$0] } ?? source.name
            return DocumentNode(
                id: nodeID, kind: source.kind, name: name, parent: parent,
                // InsertNodeCommand establishes ownership as each child enters
                // the batch. Starting empty avoids predeclaring the same child
                // identity twice while preserving source sibling indices.
                // OD-038 (ADR-0087): no translation keyed to this project's default language.
                childIDs: [], properties: SiteTranslationEditing.pastableProperties(properties, into: document.localization)
            )
        }

        if let target = slotTarget {
            // OD-018: pasted roots become this slot's top-level items, stored
            // slot-local, within the slot's rules; the slot is marked supplied.
            let rootIDs = Set(envelope.roots.compactMap { nodeMap[$0] })
            let worldNodeIDs = Self.worldPositionedNodeIDs(translated, roots: rootIDs)
            let origins = Dictionary(uniqueKeysWithValues: ResponsiveBreakpoint.allCases.map { breakpoint in
                (breakpoint, CanonicalSlotGeometry.slotOffset(instance: container, slot: target.slot.id, page: page,
                                                              document: document, breakpoint: breakpoint))
            })
            let zero = WorldVector(dx: 0, dy: 0)
            translated = translated.map { node in
                // Every pasted object outside a pasted copy's own slot
                // contents arrives in world positions and becomes slot-local;
                // a pasted copy's own contents are already slot-local.
                guard worldNodeIDs.contains(node.id) else { return node }
                var item = CanonicalSlotGeometry.shifted(node, sign: -1) { origins[$0] ?? zero }
                guard rootIDs.contains(node.id) else { return item }
                item.properties.removeAll { $0.key.rawValue == CanonicalComponentSlot.supplyKey }
                item.properties.append(.init(key: .init(rawValue: CanonicalComponentSlot.supplyKey),
                                             value: .string(target.slot.id.description), origin: .authored))
                return item
            }
            let roots = target.existing + translated.filter { rootIDs.contains($0.id) }
            if let violation = target.slot.rules.violation(for: roots) {
                throw ClipboardTransferError.unavailable("This slot does not accept that: \(violation.summary). Nothing was pasted.")
            }
        } else if CanonicalComponentSlot.suppliedNodeIDs(in: page).contains(containerID) {
            // OD-018: pasting into a copy's slot contents stores slot-local
            // geometry, so the content appears where it was placed.
            let offsets = CanonicalSlotGeometry.offsetsByBreakpoint(in: page, document: document)
            let zero = WorldVector(dx: 0, dy: 0)
            let worldNodeIDs = Self.worldPositionedNodeIDs(
                translated, roots: Set(envelope.roots.compactMap { nodeMap[$0] }))
            translated = translated.map { node in
                guard worldNodeIDs.contains(node.id) else { return node }
                return CanonicalSlotGeometry.shifted(node, sign: -1) { offsets[$0]?[containerID] ?? zero }
            }
        }
        if page.role == .componentDefinition {
            // OD-034: pasting into the definition being edited must not make
            // it contain itself or exceed the nesting limits; name the chain.
            let pasted = translated.compactMap(CanonicalComponentReference.definitionID)
            if let violation = CanonicalComponentGraph.violation(adding: pasted, into: page.id,
                definitions: document.componentDefinitions + componentPlan.importedDefinitions) {
                throw ClipboardTransferError.componentNesting(violation)
            }
        }
        var commands: [DocumentCommand] = []
        if resultingTokens != document.colorTokens { commands.append(.setColorTokens(.init(tokens: resultingTokens))) }
        if let target = slotTarget {
            commands.append(.setProperty(.init(pageID: page.id, nodeID: containerID, property: .init(
                id: target.marker?.id ?? PropertyID(), key: .init(rawValue: CanonicalComponentSlot.overrideKey(target.slot.id)),
                value: .string(CanonicalComponentSlot.suppliedValue), origin: .authored))))
        }
        commands.append(contentsOf: assetCommands)
        commands.append(contentsOf: componentPlan.importedDefinitions.enumerated().map { offset, definition in
            .insertPage(.init(page: Self.installing(styles: importedStyles, into: definition,
                onlyWhen: offset == 0), index: document.pages.count + offset))
        })
        var rootOffset = 0
        for node in translated {
            guard let sourceID = sourceIDByNodeID[node.id],
                  let source = envelope.nodes.first(where: { $0.id == sourceID }) else {
                throw ClipboardTransferError.invalidEnvelope
            }
            let index: Int
            if rootSet.contains(sourceID) {
                index = insertionIndex + rootOffset; rootOffset += 1
            } else if case .node(let oldParent) = source.parent,
                      let parent = envelope.nodes.first(where: { $0.id == oldParent }),
                      let siblingIndex = parent.childIDs.firstIndex(of: source.id) {
                index = siblingIndex
            } else {
                throw ClipboardTransferError.invalidEnvelope
            }
            commands.append(.insertNode(.init(pageID: page.id, node: node, index: index)))
        }
        var finalCommands = commands
        if componentPlan.importedDefinitions.isEmpty, !importedStyles.isEmpty,
           let firstRootID = envelope.roots.first, let translatedRootID = nodeMap[firstRootID],
           let root = translated.first(where: { $0.id == translatedRootID }) {
            for property in Self.styleDefinitionProperties(importedStyles) {
                finalCommands.append(.setProperty(.init(pageID: page.id, nodeID: root.id, property: property)))
            }
        }
        return .init(
            documentID: document.id, revision: document.revision,
            command: .batch(finalCommands), insertedRootIDs: envelope.roots.compactMap { nodeMap[$0] },
            resources: resourceDependencies, skippedDependencies: [], componentSummary: componentPlan.summary
        )
    }

    func prepareCutRemoval(
        envelope: SiteForgeClipboardEnvelope,
        identity: ClipboardOperationIdentity,
        document: CanonicalDocument,
        context: ClipboardValidationContext
    ) throws -> DocumentCommand {
        guard identity == context.liveIdentity, context.lifecycleAvailable,
              envelope.sourceDocumentID == document.id,
              envelope.sourcePageID == identity.pageID,
              let page = document.pages.first(where: { $0.id == identity.pageID }),
              envelope.roots.allSatisfy({ identity.selectedNodeIDs.contains($0) }),
              envelope.roots.allSatisfy({ !page.rootNodeIDs.contains($0) }),
              envelope.nodes.allSatisfy({ node in
                  page.nodes.contains(where: { $0.id == node.id && !$0.selectionBooleanProperty("locked") })
              }) else {
            throw ClipboardTransferError.stale
        }
        var commands: [DocumentCommand] = envelope.nodes.reversed().map {
            .removeNode(.init(pageID: identity.pageID, nodeID: $0.id))
        }
        // OD-018: cutting every top-level item of a copy's slot leaves the
        // slot authored empty (never "supplied" with nothing).
        let removed = Set(envelope.nodes.map(\.id))
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        for owner in page.nodes where owner.kind == .component && !removed.contains(owner.id) {
            for (slot, roots) in CanonicalComponentSlot.suppliedRoots(of: owner, nodesByID: byID)
                where roots.allSatisfy({ removed.contains($0.id) }) {
                guard let marker = CanonicalComponentSlot.markers(on: owner)[slot] else { continue }
                commands.append(.setProperty(.init(pageID: page.id, nodeID: owner.id, property: .init(
                    id: marker.id, key: marker.key, value: .string(CanonicalComponentSlot.emptyValue), origin: .authored))))
            }
        }
        return .batch(commands)
    }

    private static func transferredActionTarget(_ target: CanonicalLinkTarget, isCrossProject: Bool,
        pageMap: [PageID: PageID], nodeMap: [NodeID: NodeID],
        sourcePageID: PageID, destinationPageID: PageID) throws -> CanonicalLinkTarget {
        switch target {
        case .none: return .none
        case .external(let url):
            guard CanonicalLinkTarget.validateExternal(url) else { throw ClipboardTransferError.invalidEnvelope }
            return .external(url)
        case .page(let id):
            if !isCrossProject { return target }
            guard let mapped = pageMap[id] else { throw ClipboardTransferError.unmappedActionDestination }
            return .page(mapped)
        case .section(let pageID, let nodeID):
            if !isCrossProject {
                guard pageID == sourcePageID, let mapped = nodeMap[nodeID] else { return target }
                return .section(pageID: destinationPageID, nodeID: mapped)
            }
            guard let mappedPage = pageMap[pageID], let mappedNode = nodeMap[nodeID] else {
                throw ClipboardTransferError.unmappedActionDestination
            }
            return .section(pageID: mappedPage, nodeID: mappedNode)
        }
    }

    private static func prepareComponentImport(
        envelope: SiteForgeClipboardEnvelope,
        document: CanonicalDocument,
        isCrossProject: Bool,
        assetMap: [AssetID: AssetID],
        tokenMap: [ColorTokenID: ColorTokenID],
        styleMap: [ReusableStyleID: ReusableStyleID],
        pageReferenceMap: [PageID: PageID], nodeReferenceMap: [NodeID: NodeID]
    ) throws -> ClipboardComponentImportPlan {
        guard !envelope.componentDefinitions.isEmpty else {
            return .init(definitionMap: [:], definitionNameMap: [:], textPropertyMap: [:], visibilityPropertyMap: [:], choicePropertyMap: [:], mediaPropertyMap: [:], actionPropertyMap: [:], definitionNodeMap: [:],
                         importedDefinitions: [], summary: nil)
        }
        if !isCrossProject {
            let definitions = Dictionary(uniqueKeysWithValues: document.componentDefinitions.map { ($0.id, $0) })
            guard envelope.componentDefinitions.allSatisfy({ definitions[$0.id] != nil }) else {
                throw ClipboardTransferError.invalidDependency
            }
            var text: [ComponentTextPropertyID: ComponentTextPropertyID] = [:]
            var visibility: [ComponentVisibilityPropertyID: ComponentVisibilityPropertyID] = [:]
            var choice: [ComponentChoicePropertyID: ComponentChoicePropertyID] = [:]
            var media: [ComponentMediaPropertyID: ComponentMediaPropertyID] = [:]
            var action: [ComponentActionPropertyID: ComponentActionPropertyID] = [:]
            for definition in envelope.componentDefinitions {
                guard let live = definitions[definition.id] else { throw ClipboardTransferError.invalidDependency }
                let liveActions = Dictionary(uniqueKeysWithValues: CanonicalComponentAction.properties(in: live).map { ($0.id, $0.sourceNodeID) })
                for binding in CanonicalComponentAction.properties(in: definition) {
                    guard liveActions[binding.id] == binding.sourceNodeID else {
                        throw ClipboardTransferError.invalidDependency
                    }
                }
                let liveSlots = Dictionary(uniqueKeysWithValues: CanonicalComponentSlot.properties(in: live).map { ($0.id, $0.sourceNodeID) })
                for binding in CanonicalComponentSlot.properties(in: definition) {
                    guard liveSlots[binding.id] == binding.sourceNodeID else { throw ClipboardTransferError.invalidDependency }
                }
                CanonicalComponentText.properties(in: definition).forEach { text[$0.id] = $0.id }
                CanonicalComponentVisibility.properties(in: definition).forEach { visibility[$0.id] = $0.id }
                CanonicalComponentChoice.properties(in: definition).forEach { choice[$0.id] = $0.id }
                CanonicalComponentMedia.properties(in: definition).forEach { media[$0.id] = $0.id }
                CanonicalComponentAction.properties(in: definition).forEach { action[$0.id] = $0.id }
            }
            let slots = Dictionary(envelope.componentDefinitions.flatMap(CanonicalComponentSlot.properties).map { ($0.id, $0.id) },
                                   uniquingKeysWith: { first, _ in first })
            return .init(definitionMap: Dictionary(uniqueKeysWithValues: envelope.componentDefinitions.map { ($0.id, $0.id) }),
                         definitionNameMap: Dictionary(uniqueKeysWithValues: envelope.componentDefinitions.map { ($0.id, $0.name) }),
                         textPropertyMap: text, visibilityPropertyMap: visibility, choicePropertyMap: choice, mediaPropertyMap: media, actionPropertyMap: action,
                         definitionNodeMap: Dictionary(uniqueKeysWithValues: envelope.componentDefinitions.flatMap(\.nodes).map { ($0.id, $0.id) }),
                         importedDefinitions: [], summary: nil, slotPropertyMap: slots)
        }

        let sourceAssets = Dictionary(uniqueKeysWithValues: envelope.imageDependencies.map { ($0.asset.id, $0.asset.contentHash) })
        let destinationAssets = Dictionary(uniqueKeysWithValues: document.imageAssets.map { ($0.id, $0.contentHash) })
        let sourceTokens = Dictionary(uniqueKeysWithValues: envelope.colorTokenDependencies.map {
            ($0.id, "\($0.name)|\($0.color.hexadecimalRGBA)|\($0.darkColor?.hexadecimalRGBA ?? "no-dark-variant")")
        })
        let destinationTokens = Dictionary(uniqueKeysWithValues: document.colorTokens.map {
            ($0.id, "\($0.name)|\($0.color.hexadecimalRGBA)|\($0.darkColor?.hexadecimalRGBA ?? "no-dark-variant")")
        })
        let sourceStyles = Dictionary(uniqueKeysWithValues: envelope.reusableStyleDependencies.map {
            ($0.id, styleSemantic(name: $0.name, fill: $0.fill, opacity: $0.opacity, box: $0.box))
        })
        let destinationStyleIndex = try CanonicalReusableStyleIndex(document: document)
        let destinationStyles = Dictionary(uniqueKeysWithValues: destinationStyleIndex.orderedDefinitions.map {
            ($0.id, styleSemantic(name: $0.name, fill: $0.fill, opacity: $0.opacity, box: $0.box))
        })
        var destinationFingerprints: [String: [DocumentPage]] = [:]
        for definition in document.componentDefinitions {
            let fingerprint = try definitionFingerprint(
                definition, assets: destinationAssets, tokens: destinationTokens, styles: destinationStyles)
            destinationFingerprints[fingerprint, default: []].append(definition)
        }

        var definitionMap: [PageID: PageID] = [:]
        var definitionNameMap: [PageID: String] = [:]
        var textMap: [ComponentTextPropertyID: ComponentTextPropertyID] = [:]
        var visibilityMap: [ComponentVisibilityPropertyID: ComponentVisibilityPropertyID] = [:]
        var choiceMap: [ComponentChoicePropertyID: ComponentChoicePropertyID] = [:]
        var mediaMap: [ComponentMediaPropertyID: ComponentMediaPropertyID] = [:]
        var actionMap: [ComponentActionPropertyID: ComponentActionPropertyID] = [:]
        var definitionNodes: [NodeID: NodeID] = [:]
        var slotMap: [ComponentSlotPropertyID: ComponentSlotPropertyID] = [:]
        var imported: [DocumentPage] = []
        var importedByFingerprint: [String: DocumentPage] = [:]
        var entries: [ClipboardComponentTransferSummary.Entry] = []
        var reservedNames = Set(document.componentDefinitions.map { $0.name.lowercased() })

        // OD-034: import inner definitions before the definitions that contain
        // them, so each inner link and its authored values map to the
        // destination definition. A destination stored inside an inner
        // instance's action value cannot be translated between projects yet.
        let importGraph = CanonicalComponentGraph(definitions: envelope.componentDefinitions)
        let importOrder = importGraph.dependenciesFirst()
        let sourcesByID = Dictionary(uniqueKeysWithValues: envelope.componentDefinitions.map { ($0.id, $0) })
        guard !envelope.componentDefinitions.flatMap(\.nodes).contains(where: { node in
            node.kind == .component && node.properties.contains { CanonicalComponentAction.overrideID($0.key.rawValue) != nil }
        }) else { throw ClipboardTransferError.unsupportedComponentDependency }
        for source in importOrder.compactMap({ sourcesByID[$0] }) {
            var nestedKeys: [String: String] = [:]
            textMap.forEach { nestedKeys[CanonicalComponentText.overrideKey($0.key)] = CanonicalComponentText.overrideKey($0.value) }
            visibilityMap.forEach { nestedKeys[CanonicalComponentVisibility.overrideKey($0.key)] = CanonicalComponentVisibility.overrideKey($0.value) }
            choiceMap.forEach { nestedKeys[CanonicalComponentChoice.overrideKey($0.key)] = CanonicalComponentChoice.overrideKey($0.value) }
            mediaMap.forEach { nestedKeys[CanonicalComponentMedia.overrideKey($0.key)] = CanonicalComponentMedia.overrideKey($0.value) }
            slotMap.forEach { nestedKeys[CanonicalComponentSlot.overrideKey($0.key)] = CanonicalComponentSlot.overrideKey($0.value) }
            for node in source.nodes where node.kind.isLinkControl {
                let target = try CanonicalLinkTarget.resolve(node)
                _ = try transferredActionTarget(target, isCrossProject: true,
                    pageMap: pageReferenceMap.merging([source.id: source.id], uniquingKeysWith: { first, _ in first }),
                    nodeMap: nodeReferenceMap.merging(Dictionary(uniqueKeysWithValues: source.nodes.map { ($0.id, $0.id) }), uniquingKeysWith: { first, _ in first }),
                    sourcePageID: envelope.sourcePageID, destinationPageID: pageReferenceMap[envelope.sourcePageID] ?? envelope.sourcePageID)
            }
            let fingerprint = try definitionFingerprint(source, assets: sourceAssets, tokens: sourceTokens, styles: sourceStyles,
                pageReferenceMap: pageReferenceMap, nodeReferenceMap: nodeReferenceMap,
                definitionMap: definitionMap, overrideKeyMap: nestedKeys, slotMap: slotMap)
            if let destination = destinationFingerprints[fingerprint]?.sorted(by: { $0.id.description < $1.id.description }).first {
                definitionMap[source.id] = destination.id
                definitionNameMap[source.id] = destination.name
                try mapEquivalentBindings(source: source, destination: destination,
                                          text: &textMap, visibility: &visibilityMap, choice: &choiceMap, media: &mediaMap,
                                          action: &actionMap, nodes: &definitionNodes)
                try mapEquivalentSlots(source: source, destination: destination, slots: &slotMap)
                entries.append(.init(sourceDefinitionID: source.id, destinationDefinitionID: destination.id,
                                     displayName: destination.name, resolution: .reused))
                continue
            }
            if let destination = importedByFingerprint[fingerprint] {
                definitionMap[source.id] = destination.id
                definitionNameMap[source.id] = destination.name
                try mapEquivalentBindings(source: source, destination: destination,
                                          text: &textMap, visibility: &visibilityMap, choice: &choiceMap, media: &mediaMap,
                                          action: &actionMap, nodes: &definitionNodes)
                try mapEquivalentSlots(source: source, destination: destination, slots: &slotMap)
                entries.append(.init(sourceDefinitionID: source.id, destinationDefinitionID: destination.id,
                                     displayName: destination.name, resolution: .reused))
                continue
            }
            let destinationID = PageID()
            let renamed = reservedNames.contains(source.name.lowercased())
            let name = renamed
                ? ComponentDefinitionGraphCopy.uniqueCopyName(source.name, reserved: reservedNames)
                : source.name
            reservedNames.insert(name.lowercased())
            let translated: DocumentPage
            do {
                translated = try ComponentDefinitionGraphCopy.remap(
                    source, destinationID: destinationID, name: name,
                    assetMap: assetMap, tokenMap: tokenMap, styleMap: styleMap,
                    textMap: &textMap, visibilityMap: &visibilityMap, choiceMap: &choiceMap, mediaMap: &mediaMap,
                    actionMap: &actionMap, slotMap: &slotMap, definitionNodes: &definitionNodes,
                    pageReferenceMap: pageReferenceMap, nodeReferenceMap: nodeReferenceMap,
                    definitionMap: definitionMap
                )
            } catch ComponentDefinitionGraphCopy.Failure.invalidGraph {
                throw ClipboardTransferError.invalidEnvelope
            } catch ComponentDefinitionGraphCopy.Failure.missingDependency {
                throw ClipboardTransferError.invalidDependency
            }
            definitionMap[source.id] = destinationID
            definitionNameMap[source.id] = name
            // OD-038 (ADR-0087): like pasted elements, an imported definition keeps
            // no translation keyed to this project's default language.
            let pastable = SiteTranslationEditing.pastablePage(translated, into: document.localization)
            imported.append(pastable)
            importedByFingerprint[fingerprint] = pastable
            entries.append(.init(sourceDefinitionID: source.id, destinationDefinitionID: destinationID,
                                 displayName: name, resolution: renamed ? .renamed : .imported))
        }
        return .init(definitionMap: definitionMap, definitionNameMap: definitionNameMap, textPropertyMap: textMap,
                     visibilityPropertyMap: visibilityMap, choicePropertyMap: choiceMap, mediaPropertyMap: mediaMap,
                     actionPropertyMap: actionMap, definitionNodeMap: definitionNodes, importedDefinitions: imported,
                     summary: .init(entries: entries), slotPropertyMap: slotMap)
    }

    private static func orderedNodes(_ definition: DocumentPage) throws -> [DocumentNode] {
        let byID = Dictionary(uniqueKeysWithValues: definition.nodes.map { ($0.id, $0) })
        guard let root = definition.rootNodeIDs.first else { throw ClipboardTransferError.invalidEnvelope }
        var result: [DocumentNode] = [], visited = Set<NodeID>(), pending = [root]
        while let id = pending.popLast() {
            guard visited.insert(id).inserted, let node = byID[id] else { throw ClipboardTransferError.invalidEnvelope }
            result.append(node); pending.append(contentsOf: node.childIDs.reversed())
        }
        guard result.count == definition.nodes.count else { throw ClipboardTransferError.invalidEnvelope }
        return result
    }

    private static func definitionFingerprint(
        _ definition: DocumentPage,
        assets: [AssetID: String],
        tokens: [ColorTokenID: String],
        styles: [ReusableStyleID: String],
        pageReferenceMap: [PageID: PageID] = [:], nodeReferenceMap: [NodeID: NodeID] = [:],
        definitionMap: [PageID: PageID] = [:], overrideKeyMap: [String: String] = [:],
        slotMap: [ComponentSlotPropertyID: ComponentSlotPropertyID] = [:]
    ) throws -> String {
        let nodes = try orderedNodes(definition)
        let nodeIndex = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element.id, $0.offset) })
        var material: [String] = []
        for (index, node) in nodes.enumerated() {
            let parent = switch node.parent {
            case .page: "root"
            case .node(let id): "node:\(nodeIndex[id] ?? -1)"
            }
            material.append("node|\(index)|\(node.kind.rawValue)|\(node.name)|\(parent)|\(node.childIDs.compactMap { nodeIndex[$0] }.map(String.init).joined(separator: ","))")
            // OD-034: an inner instance's link and value keys are compared in
            // destination terms, so a reused inner definition matches.
            for property in node.properties.sorted(by: {
                (overrideKeyMap[$0.key.rawValue] ?? $0.key.rawValue) < (overrideKeyMap[$1.key.rawValue] ?? $1.key.rawValue)
            }) {
                let key = overrideKeyMap[property.key.rawValue] ?? property.key.rawValue
                if key.hasPrefix(CanonicalReusableStyleIndex.namespace + "definition.") { continue }
                let value: String
                if key == CanonicalComponentReference.key, case .string(let raw) = property.value,
                   let id = PageID(uuidString: raw), let mapped = definitionMap[id] {
                    value = propertyValueMaterial(.string(mapped.description))
                } else if key == CanonicalComponentSlot.supplyKey, case .string(let raw) = property.value,
                          let id = ComponentSlotPropertyID(uuidString: raw), let mapped = slotMap[id] {
                    value = propertyValueMaterial(.string(mapped.description))
                } else if key == CanonicalComponentText.namespace + "id" { value = "text-binding:\(index)"
                } else if key == CanonicalComponentVisibility.namespace + "id" { value = "visibility-binding:\(index)"
                } else if key == CanonicalComponentChoice.namespace + "id" { value = "choice-binding:\(index)"
                } else if key == CanonicalComponentMedia.namespace + "id" { value = "media-binding:\(index)"
                } else if key == CanonicalComponentAction.namespace + "id" { value = "action-binding:\(index)"
                } else if key == CanonicalComponentSlot.namespace + "id" { value = "slot-binding:\(index)"
                } else if key.hasPrefix(CanonicalComponentOrganization.namespace), key.hasSuffix(".binding"),
                          case .string(let raw) = property.value, let identity = ComponentOverridePropertyIdentity.reference(raw) {
                    value = "organization-binding:\(index):\(identity.organizationKind)"
                } else if [CanonicalImageStyle.namespace + "assetID", CanonicalImageFill.assetKey].contains(key)
                            || SiteTranslationKey(rawValue: key)?.field == .imageAssetID,
                          case .string(let raw) = property.value, let id = AssetID(uuidString: raw), let semantic = assets[id] {
                    value = "asset:\(semantic)"
                } else if key.hasPrefix(LocalColorTokenBinding.prefix), case .string(let raw) = property.value,
                          let id = ColorTokenID(uuidString: raw), let semantic = tokens[id] {
                    value = "token:\(semantic)"
                } else if key == CanonicalReusableStyleIndex.appliedKey, case .string(let raw) = property.value {
                    value = "styles:" + (try raw.split(separator: ",", omittingEmptySubsequences: false).map { part in
                        guard let id = ReusableStyleID(uuidString: String(part)), let semantic = styles[id] else {
                            throw ClipboardTransferError.invalidDependency
                        }
                        return semantic
                    }).joined(separator: ",")
                } else if key == CanonicalLinkTarget.namespace + "nodeID", case .string(let raw) = property.value,
                          let id = NodeID(uuidString: raw), let mapped = nodeIndex[id] {
                    value = "node:\(mapped)"
                } else if key == CanonicalLinkTarget.namespace + "pageID", case .string(let raw) = property.value,
                          PageID(uuidString: raw) == definition.id { value = "page:self"
                } else if key == CanonicalLinkTarget.namespace + "pageID", case .string(let raw) = property.value,
                          let id = PageID(uuidString: raw), let mapped = pageReferenceMap[id] { value = "s:\(mapped.description.utf8.count):\(mapped.description)"
                } else if key == CanonicalLinkTarget.namespace + "nodeID", case .string(let raw) = property.value,
                          let id = NodeID(uuidString: raw), let mapped = nodeReferenceMap[id] { value = "s:\(mapped.description.utf8.count):\(mapped.description)"
                } else if key == CanonicalEventGraph.interactionsKey, case .string(let raw) = property.value,
                          let interactions = try? CanonicalEventGraph.decode(raw) {
                    // OD-039: every copy has its own interaction identities, so a
                    // structurally equal definition from another project matches.
                    value = interactionMaterial(interactions, definitionID: definition.id, nodeIndex: nodeIndex,
                                                pageReferenceMap: pageReferenceMap, nodeReferenceMap: nodeReferenceMap)
                } else { value = propertyValueMaterial(property.value) }
                material.append("property|\(index)|\(key)|\(property.origin.rawValue)|\(value)")
            }
        }
        return SHA256.hash(data: Data(material.joined(separator: "\u{0}").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// Interactions in fingerprint terms: no identities, and targets inside the
    /// definition by position (like link targets), so equal graphs compare equal.
    private static func interactionMaterial(_ interactions: [CanonicalInteraction], definitionID: PageID,
                                            nodeIndex: [NodeID: Int], pageReferenceMap: [PageID: PageID],
                                            nodeReferenceMap: [NodeID: NodeID]) -> String {
        var parts: [String] = []
        for interaction in interactions {
            var actions: [String] = []
            for action in interaction.actions {
                var target = "-", page = "-", value = "-"
                if let id = action.target {
                    if let position = nodeIndex[id] { target = "node:\(position)" } else { target = (nodeReferenceMap[id] ?? id).description }
                }
                if let id = action.page { page = id == definitionID ? "page:self" : (pageReferenceMap[id] ?? id).description }
                if let stored = action.value { value = CanonicalPageState.encode(stored) ?? "-" }
                let variable = action.variable?.uuidString.lowercased() ?? "-"
                actions.append("\(action.kind.rawValue)|\(target)|\(page)|\(variable)|\(value)")
            }
            parts.append(interaction.trigger.rawValue + "[" + actions.joined(separator: ";") + "]")
        }
        return "interactions:" + parts.joined(separator: ",")
    }

    private static func propertyValueMaterial(_ value: PropertyValue) -> String {
        switch value {
        case .string(let value): "s:\(value.utf8.count):\(value)"
        case .number(let value): "n:\(String(format: "%.17g", locale: Locale(identifier: "en_US_POSIX"), value))"
        case .boolean(let value): "b:\(value ? 1 : 0)"
        }
    }

    private static func styleSemantic(name: String, fill: CanonicalSolidColor?, opacity: Double?,
                                      box: CanonicalReusableBoxAppearance) -> String {
        "\(name)|\(fill?.hexadecimalRGBA ?? "-")|\(opacity.map { String(format: "%.17g", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "-")|\(box.semanticFingerprint)"
    }

    /// OD-018: slot identities of a reused (structurally equal) definition.
    private static func mapEquivalentSlots(source: DocumentPage, destination: DocumentPage,
                                           slots: inout [ComponentSlotPropertyID: ComponentSlotPropertyID]) throws {
        let sourceNodes = try orderedNodes(source), destinationNodes = try orderedNodes(destination)
        guard sourceNodes.count == destinationNodes.count else { throw ClipboardTransferError.invalidDependency }
        for (sourceNode, destinationNode) in zip(sourceNodes, destinationNodes) {
            if let old = CanonicalComponentSlot.property(on: sourceNode)?.id,
               let new = CanonicalComponentSlot.property(on: destinationNode)?.id { slots[old] = new }
        }
    }

    private static func mapEquivalentBindings(
        source: DocumentPage,
        destination: DocumentPage,
        text: inout [ComponentTextPropertyID: ComponentTextPropertyID],
        visibility: inout [ComponentVisibilityPropertyID: ComponentVisibilityPropertyID],
        choice: inout [ComponentChoicePropertyID: ComponentChoicePropertyID],
        media: inout [ComponentMediaPropertyID: ComponentMediaPropertyID],
        action: inout [ComponentActionPropertyID: ComponentActionPropertyID],
        nodes: inout [NodeID: NodeID]
    ) throws {
        let sourceNodes = try orderedNodes(source), destinationNodes = try orderedNodes(destination)
        guard sourceNodes.count == destinationNodes.count else { throw ClipboardTransferError.invalidDependency }
        for (sourceNode, destinationNode) in zip(sourceNodes, destinationNodes) {
            nodes[sourceNode.id] = destinationNode.id
            if let old = CanonicalComponentText.property(on: sourceNode)?.id,
               let new = CanonicalComponentText.property(on: destinationNode)?.id { text[old] = new }
            if let old = CanonicalComponentVisibility.property(on: sourceNode)?.id,
               let new = CanonicalComponentVisibility.property(on: destinationNode)?.id { visibility[old] = new }
            if let old = CanonicalComponentChoice.property(on: sourceNode)?.id,
               let new = CanonicalComponentChoice.property(on: destinationNode)?.id { choice[old] = new }
            if let old = CanonicalComponentMedia.property(on: sourceNode)?.id,
               let new = CanonicalComponentMedia.property(on: destinationNode)?.id { media[old] = new }
            if let old = CanonicalComponentAction.property(on: sourceNode)?.id,
               let new = CanonicalComponentAction.property(on: destinationNode)?.id { action[old] = new }
        }
    }

    private static func styleDefinitionProperties(_ styles: [ClipboardReusableStyleDependency]) -> [NodeProperty] {
        styles.flatMap { style -> [NodeProperty] in
            let prefix = CanonicalReusableStyleIndex.namespace + "definition.\(style.id.description)."
            var result = [NodeProperty(key: .init(rawValue: prefix + "name"), value: .string(style.name), origin: .authored)]
            if let fill = style.fill {
                result.append(NodeProperty(key: .init(rawValue: prefix + "fill"), value: .string(fill.hexadecimalRGBA), origin: .authored))
            }
            if let opacity = style.opacity {
                result.append(NodeProperty(key: .init(rawValue: prefix + "opacity"), value: .number(opacity), origin: .authored))
            }
            for entry in style.box.fieldValues {
                result.append(NodeProperty(key: .init(rawValue: prefix + entry.field), value: entry.value, origin: .authored))
            }
            return result
        }
    }

    private static func installing(
        styles: [ClipboardReusableStyleDependency], into definition: DocumentPage, onlyWhen install: Bool
    ) -> DocumentPage {
        guard install, let root = definition.rootNodeIDs.first,
              let index = definition.nodes.firstIndex(where: { $0.id == root }) else { return definition }
        var result = definition
        result.nodes[index].properties += styleDefinitionProperties(styles)
        return result
    }

    private func hasSelectedAncestor(_ id: NodeID, selected: Set<NodeID>, nodes: [NodeID: DocumentNode]) -> Bool {
        if selected.contains(id) { return true }
        guard let node = nodes[id], case .node(let parent) = node.parent else { return false }
        return hasSelectedAncestor(parent, selected: selected, nodes: nodes)
    }

    private static func assetReferences(_ node: DocumentNode) -> [AssetID] {
        CanonicalGraphReferences.assets(node)
    }

    private static func tokenReferences(_ node: DocumentNode) -> [ColorTokenID] {
        CanonicalGraphReferences.tokens(node)
    }
}

struct ClipboardDiagnosticRecord: Equatable, Sendable {
    let requirementID: String
    let operation: String
    let sanitizedObjectIdentifiers: [String]
    let objectCount: Int
    let durationMilliseconds: Double
    let resultRevision: UInt64?
    let failureCategory: String?
    // Deliberately excludes clipboard bytes, authored values, names, paths,
    // and raw stable identities. Identifier digests are one-way and bounded.
}

actor ClipboardDiagnostics {
    private var records: [ClipboardDiagnosticRecord] = []
    func append(_ value: ClipboardDiagnosticRecord) {
        records.append(value)
        if records.count > 256 { records.removeFirst(records.count - 256) }
    }
    func snapshot() -> [ClipboardDiagnosticRecord] { records }
}

enum ClipboardDiagnosticSanitizer {
    static func identifiers(for values: [NodeID]) -> [String] {
        values.prefix(SiteForgeClipboardEnvelope.maximumRoots).map { value in
            let digest = SHA256.hash(data: Data(value.description.utf8))
            return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        }
    }
}
