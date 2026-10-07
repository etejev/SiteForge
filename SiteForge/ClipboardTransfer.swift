import CryptoKit
import Foundation

// SF-0308-001...008. Clipboard bytes are an inert, bounded transfer envelope.
// They are never part of the canonical document or project package; only the
// validated result is compiled into the existing document command registry.
struct SiteForgeClipboardEnvelope: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let maximumEncodedBytes = 64 * 1_024 * 1_024
    static let maximumNodes = 10_000
    static let maximumRoots = 1_000
    static let maximumDependencies = 1_000

    let version: Int
    let sourceDocumentID: DocumentID
    let sourcePageID: PageID
    let roots: [NodeID]
    let nodes: [DocumentNode]
    let imageDependencies: [ClipboardImageDependency]
    let colorTokenDependencies: [LocalColorToken]

    init(
        version: Int = Self.currentVersion,
        sourceDocumentID: DocumentID,
        sourcePageID: PageID,
        roots: [NodeID],
        nodes: [DocumentNode],
        imageDependencies: [ClipboardImageDependency] = [],
        colorTokenDependencies: [LocalColorToken] = []
    ) {
        self.version = version
        self.sourceDocumentID = sourceDocumentID
        self.sourcePageID = sourcePageID
        self.roots = roots
        self.nodes = nodes
        self.imageDependencies = imageDependencies
        self.colorTokenDependencies = colorTokenDependencies
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, sourceDocumentID, sourcePageID, roots, nodes, imageDependencies, colorTokenDependencies
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
        try validate()
    }

    func validate() throws {
        guard version == Self.currentVersion else { throw ClipboardTransferError.unsupportedVersion }
        let properties = nodes.flatMap(\.properties)
        guard !roots.isEmpty, roots.count <= Self.maximumRoots,
              Set(roots).count == roots.count,
              !nodes.isEmpty, nodes.count <= Self.maximumNodes,
              Set(nodes.map(\.id)).count == nodes.count,
              Set(properties.map(\.id)).count == properties.count,
              imageDependencies.count + colorTokenDependencies.count <= Self.maximumDependencies,
              Set(imageDependencies.map { $0.asset.id }).count == imageDependencies.count,
              Set(colorTokenDependencies.map(\.id)).count == colorTokenDependencies.count else {
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
        let referencedAssets = Set(nodes.flatMap { node in
            [CanonicalImageStyle.namespace + "assetID", CanonicalImageFill.assetKey].compactMap {
                node.insertionStringProperty($0).flatMap(AssetID.init(uuidString:))
            }
        })
        let referencedTokens = Set(nodes.flatMap { node in
            LocalColorTarget.allCases.compactMap { LocalColorTokenBinding.id(for: node, target: $0) }
        })
        guard referencedAssets == Set(imageDependencies.map { $0.asset.id }),
              referencedTokens == Set(colorTokenDependencies.map(\.id)),
              colorTokenDependencies.allSatisfy(\.isValid) else {
            throw ClipboardTransferError.invalidDependency
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
}

struct PreparedClipboardTransfer: Sendable {
    let command: DocumentCommand
    let insertedRootIDs: [NodeID]
    let resources: [ClipboardImageDependency]
    let skippedDependencies: [String]
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
        case .unsupportedComponentDependency: "Cross-project component transfer is not yet supported. Detach the component or copy within its project."
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

        let assetIDs = Set(ordered.flatMap(Self.assetReferences))
        let assetsByID = Dictionary(uniqueKeysWithValues: document.imageAssets.map { ($0.id, $0) })
        let imageDependencies = try assetIDs.sorted { $0.description < $1.description }.map { id -> ClipboardImageDependency in
            guard let asset = assetsByID[id] else { throw ClipboardTransferError.invalidDependency }
            let (descriptor, bytes) = try resourceData(asset.resourceID)
            return .init(asset: asset, descriptor: descriptor, bytes: bytes)
        }
        let tokenIDs = Set(ordered.flatMap(Self.tokenReferences))
        let tokensByID = Dictionary(uniqueKeysWithValues: document.colorTokens.map { ($0.id, $0) })
        let tokens = try tokenIDs.sorted { $0.description < $1.description }.map {
            guard let token = tokensByID[$0] else { throw ClipboardTransferError.invalidDependency }
            return token
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
            nodes: transferableNodes, imageDependencies: imageDependencies, colorTokenDependencies: tokens
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
        if isCrossProject, envelope.nodes.contains(where: { $0.kind == .component || CanonicalComponentReference.definitionID(for: $0) != nil }) {
            throw ClipboardTransferError.unsupportedComponentDependency
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
        }
        let page = document.pages[pageIndex]
        let destination: NodeParent
        let insertionIndex: Int
        guard let containerID = context.activeContainerID,
              let container = page.nodes.first(where: { $0.id == containerID }),
              container.kind.acceptsAuthoredChildren,
              !container.selectionBooleanProperty("locked"),
              !container.selectionBooleanProperty("hidden") else {
            throw ClipboardTransferError.invalidTarget
        }
        destination = .node(containerID)
        insertionIndex = container.childIDs.count

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
            if let existing = resultingTokens.first(where: { $0.name == token.name && $0.color == token.color }) {
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
                resultingTokens.append(.init(id: newID, name: name, color: token.color))
            }
        }

        let nodeMap = Dictionary(uniqueKeysWithValues: envelope.nodes.map { ($0.id, NodeID()) })
        let sourceIDByNodeID = Dictionary(uniqueKeysWithValues: nodeMap.map { ($0.value, $0.key) })
        let propertyMap = Dictionary(uniqueKeysWithValues: envelope.nodes.flatMap(\.properties).map { ($0.id, PropertyID()) })
        let rootSet = Set(envelope.roots)
        let translated = try envelope.nodes.map { source -> DocumentNode in
            guard let nodeID = nodeMap[source.id] else { throw ClipboardTransferError.invalidEnvelope }
            let parent: NodeParent
            if rootSet.contains(source.id) { parent = destination }
            else if case .node(let oldParent) = source.parent, let newParent = nodeMap[oldParent] { parent = .node(newParent) }
            else { throw ClipboardTransferError.invalidEnvelope }
            let properties = try source.properties.map { property in
                guard let propertyID = propertyMap[property.id] else {
                    throw ClipboardTransferError.invalidEnvelope
                }
                var value = property.value
                let key = property.key.rawValue
                if [CanonicalImageStyle.namespace + "assetID", CanonicalImageFill.assetKey].contains(key),
                   case .string(let raw) = value, let old = AssetID(uuidString: raw), let mapped = assetMap[old] {
                    value = .string(mapped.description)
                } else if key.hasPrefix(LocalColorTokenBinding.prefix), case .string(let raw) = value,
                          let old = ColorTokenID(uuidString: raw), let mapped = tokenMap[old] {
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
                }
                if rootSet.contains(source.id), placement == .offset,
                   [GeometryInspectorField.x.propertyKey, GeometryInspectorField.y.propertyKey].contains(key),
                   case .number(let number) = value { value = .number(number + 20) }
                return NodeProperty(id: propertyID, key: property.key, value: value, origin: property.origin)
            }
            return DocumentNode(
                id: nodeID, kind: source.kind, name: source.name, parent: parent,
                // InsertNodeCommand establishes ownership as each child enters
                // the batch. Starting empty avoids predeclaring the same child
                // identity twice while preserving source sibling indices.
                childIDs: [], properties: properties
            )
        }

        var commands: [DocumentCommand] = []
        if resultingTokens != document.colorTokens { commands.append(.setColorTokens(.init(tokens: resultingTokens))) }
        commands.append(contentsOf: assetCommands)
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
        return .init(
            command: .batch(commands), insertedRootIDs: envelope.roots.compactMap { nodeMap[$0] },
            resources: resourceDependencies, skippedDependencies: []
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
        return .batch(envelope.nodes.reversed().map {
            .removeNode(.init(pageID: identity.pageID, nodeID: $0.id))
        })
    }

    private func hasSelectedAncestor(_ id: NodeID, selected: Set<NodeID>, nodes: [NodeID: DocumentNode]) -> Bool {
        if selected.contains(id) { return true }
        guard let node = nodes[id], case .node(let parent) = node.parent else { return false }
        return hasSelectedAncestor(parent, selected: selected, nodes: nodes)
    }

    private static func assetReferences(_ node: DocumentNode) -> [AssetID] {
        [CanonicalImageStyle.namespace + "assetID", CanonicalImageFill.assetKey].compactMap {
            node.insertionStringProperty($0).flatMap(AssetID.init(uuidString:))
        }
    }

    private static func tokenReferences(_ node: DocumentNode) -> [ColorTokenID] {
        LocalColorTarget.allCases.compactMap { LocalColorTokenBinding.id(for: node, target: $0) }
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
