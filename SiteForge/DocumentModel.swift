import CryptoKit
import Foundation

/// Canonical v1 structural-layout tokens shared by model validation,
/// deterministic layout resolution, and the Inspector command registry.
enum ContainerLayoutAxis: String, CaseIterable, Sendable { case vertical, horizontal }
enum ContainerLayoutAlignment: String, CaseIterable, Sendable { case start, center, end, stretch }

protocol StableIdentifierDomain: Sendable {
    static var diagnosticNamespace: String { get }
}

struct StableIdentifier<Domain: StableIdentifierDomain>: Codable, Hashable, CustomStringConvertible, Sendable {
    let rawValue: UUID

    init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    init?(uuidString: String) {
        guard let value = UUID(uuidString: uuidString) else { return nil }
        self.init(value)
    }

    var description: String { rawValue.uuidString.lowercased() }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let uuid = UUID(uuidString: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a UUID string"
            )
        }
        rawValue = uuid
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

enum DocumentIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "document"
}

enum PageIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "page"
}

enum NodeIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "node"
}

enum PropertyIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "property"
}

enum TemplateIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "template"
}

enum GuideIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "guide"
}

enum ResourceIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "resource"
}

enum AssetIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "asset"
}

typealias DocumentID = StableIdentifier<DocumentIdentifierDomain>
typealias PageID = StableIdentifier<PageIdentifierDomain>
typealias NodeID = StableIdentifier<NodeIdentifierDomain>
typealias PropertyID = StableIdentifier<PropertyIdentifierDomain>
typealias TemplateID = StableIdentifier<TemplateIdentifierDomain>
typealias GuideID = StableIdentifier<GuideIdentifierDomain>
typealias ResourceID = StableIdentifier<ResourceIdentifierDomain>
typealias AssetID = StableIdentifier<AssetIdentifierDomain>

enum ImageAssetFormat: String, Codable, CaseIterable, Sendable {
    case png, jpeg, gif, tiff, heic

    var mediaType: String {
        switch self {
        case .png: "image/png"
        case .jpeg: "image/jpeg"
        case .gif: "image/gif"
        case .tiff: "image/tiff"
        case .heic: "image/heic"
        }
    }
}

enum ImageAssetProvenance: String, Codable, Sendable {
    case imported
}

/// Canonical image-library metadata. Original bytes remain in the existing
/// content-addressed resource store; canonical state never retains a user
/// path, a decoded bitmap, or an editor thumbnail.
struct ImageAsset: Codable, Equatable, Identifiable, Sendable {
    static let maximumAssetCount = 2_000
    static let maximumResourceBytes = 16 * 1_024 * 1_024
    static let maximumDisplayNameBytes = 1_024
    static let maximumOriginalFilenameBytes = 1_024
    static let maximumPixelDimension = 65_535

    let id: AssetID
    var resourceID: ResourceID
    var displayName: String
    var originalFilename: String
    var format: ImageAssetFormat
    var pixelWidth: Int
    var pixelHeight: Int
    var byteCount: Int
    var contentHash: String
    var provenance: ImageAssetProvenance

    init(
        id: AssetID = AssetID(), resourceID: ResourceID,
        displayName: String, originalFilename: String,
        format: ImageAssetFormat, pixelWidth: Int, pixelHeight: Int,
        byteCount: Int, contentHash: String,
        provenance: ImageAssetProvenance = .imported
    ) {
        self.id = id
        self.resourceID = resourceID
        self.displayName = displayName
        self.originalFilename = originalFilename
        self.format = format
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteCount = byteCount
        self.contentHash = contentHash
        self.provenance = provenance
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, resourceID, displayName, originalFilename, format, pixelWidth,
             pixelHeight, byteCount, contentHash, provenance
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder, when: SiteForgeDecodingPolicy.requiresExactKeys(decoder))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(AssetID.self, forKey: .id)
        resourceID = try container.decode(ResourceID.self, forKey: .resourceID)
        displayName = try container.decode(String.self, forKey: .displayName)
        originalFilename = try container.decode(String.self, forKey: .originalFilename)
        format = try container.decode(ImageAssetFormat.self, forKey: .format)
        pixelWidth = try container.decode(Int.self, forKey: .pixelWidth)
        pixelHeight = try container.decode(Int.self, forKey: .pixelHeight)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        contentHash = try container.decode(String.self, forKey: .contentHash)
        provenance = try container.decode(ImageAssetProvenance.self, forKey: .provenance)
    }

    func validate() throws {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              displayName.utf8.count <= Self.maximumDisplayNameBytes,
              !originalFilename.isEmpty,
              originalFilename.utf8.count <= Self.maximumOriginalFilenameBytes,
              !originalFilename.contains("/"), !originalFilename.contains("\\"),
              (1...Self.maximumPixelDimension).contains(pixelWidth),
              (1...Self.maximumPixelDimension).contains(pixelHeight),
              byteCount > 0, byteCount <= Self.maximumResourceBytes,
              contentHash.count == 64,
              contentHash == contentHash.lowercased(),
              contentHash.allSatisfy(\.isHexDigit) else {
            throw ModelValidationError.invalidImageAsset
        }
    }
}

enum ImageFitMode: String, Codable, CaseIterable, Sendable {
    case fit, fill, stretch
}

enum GuideAxis: String, Codable, CaseIterable, Sendable {
    case horizontal
    case vertical
}

enum GuideProvenance: String, Codable, Sendable {
    case authored
}

struct AuthoredGuide: Codable, Equatable, Identifiable, Sendable {
    static let maximumCoordinate = 1_000_000_000.0

    let id: GuideID
    let pageID: PageID
    var axis: GuideAxis
    var position: Double
    var provenance: GuideProvenance

    init(
        id: GuideID = GuideID(),
        pageID: PageID,
        axis: GuideAxis,
        position: Double,
        provenance: GuideProvenance = .authored
    ) {
        self.id = id
        self.pageID = pageID
        self.axis = axis
        self.position = position
        self.provenance = provenance
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, pageID, axis, position, provenance
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder, when: SiteForgeDecodingPolicy.requiresExactKeys(decoder))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(GuideID.self, forKey: .id)
        pageID = try container.decode(PageID.self, forKey: .pageID)
        axis = try container.decode(GuideAxis.self, forKey: .axis)
        position = try container.decode(Double.self, forKey: .position)
        provenance = try container.decode(GuideProvenance.self, forKey: .provenance)
    }
}

struct PropertyKey: Codable, Hashable, RawRepresentable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        // `RawRepresentable` keys have always been encoded as one JSON string.
        // Keep that stable wire form; a keyed decoder here would make every
        // existing current-schema property invalid rather than stricter.
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum PropertyValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)

    private enum CodingKeys: String, CodingKey, CaseIterable { case string, number, boolean }
    private enum PayloadKeys: String, CodingKey, CaseIterable { case _0 }

    init(from decoder: Decoder) throws {
        let strict = SiteForgeDecodingPolicy.requiresExactKeys(decoder)
        if strict { try requireExactlyOneCase(CodingKeys.self, in: decoder) }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cases = container.allKeys
        guard cases.count == 1, let key = cases.first else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Property values require exactly one case.")
            )
        }
        let payloadDecoder = try container.superDecoder(forKey: key)
        try requireExactKeys(PayloadKeys.self, in: payloadDecoder, when: strict)
        let payload = try payloadDecoder.container(keyedBy: PayloadKeys.self)
        switch key {
        case .string: self = .string(try payload.decode(String.self, forKey: ._0))
        case .number: self = .number(try payload.decode(Double.self, forKey: ._0))
        case .boolean: self = .boolean(try payload.decode(Bool.self, forKey: ._0))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let value):
            var payload = container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .string)
            try payload.encode(value, forKey: ._0)
        case .number(let value):
            var payload = container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .number)
            try payload.encode(value, forKey: ._0)
        case .boolean(let value):
            var payload = container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .boolean)
            try payload.encode(value, forKey: ._0)
        }
    }
}

enum PropertyOrigin: String, Codable, Equatable, Sendable {
    case defaulted
    case authored
}

struct NodeProperty: Codable, Equatable, Identifiable, Sendable {
    let id: PropertyID
    var key: PropertyKey
    var value: PropertyValue
    var origin: PropertyOrigin

    init(
        id: PropertyID = PropertyID(),
        key: PropertyKey,
        value: PropertyValue,
        origin: PropertyOrigin = .authored
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.origin = origin
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, key, value, origin }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder, when: SiteForgeDecodingPolicy.requiresExactKeys(decoder))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(PropertyID.self, forKey: .id)
        key = try container.decode(PropertyKey.self, forKey: .key)
        value = try container.decode(PropertyValue.self, forKey: .value)
        origin = try container.decode(PropertyOrigin.self, forKey: .origin)
    }
}

enum NodeKind: String, Codable, CaseIterable, Sendable {
    case frame
    case text
    /// Semantic containers introduced by SF-AUTHORING-010. Their layout
    /// semantics are represented by explicit, versioned default properties;
    /// editor state never participates in this representation.
    case section
    case stack
    case grid
    case image
    case component

    var acceptsAuthoredChildren: Bool {
        switch self {
        case .frame, .section, .stack, .grid: true
        case .text, .image, .component: false
        }
    }
}

// SF-0507-001...008 — typography is canonical document data, so its closed
// value types live in the headless model boundary. Installed-font resolution
// remains an AppKit concern and is deliberately not serialized.
enum CanonicalFontWeight: String, CaseIterable, Sendable {
    case regular, medium, semibold, bold
}

enum CanonicalTextAlignment: String, CaseIterable, Sendable {
    case leading, center, trailing
}

struct CanonicalTypography: Equatable, Sendable {
    static let namespace = "style.typography.v1."
    static let defaultFamily = "System"
    static let defaultValue = CanonicalTypography(
        family: defaultFamily, weight: .regular, size: 14,
        lineHeight: 17, tracking: 0, alignment: .leading
    )
    let family: String
    let weight: CanonicalFontWeight
    let size: Double
    let lineHeight: Double
    let tracking: Double
    let alignment: CanonicalTextAlignment

    var isValid: Bool {
        let trimmed = family.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed == family && family.utf8.count <= 128
            && family.rangeOfCharacter(from: .controlCharacters) == nil
            && [size, lineHeight, tracking].allSatisfy(\.isFinite)
            && (1...1_000).contains(size)
            && (1...2_000).contains(lineHeight)
            && lineHeight >= size * 0.5
            && (-100...100).contains(tracking)
    }
}

struct PageRoute: Codable, Equatable, Hashable, RawRepresentable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        // Routes are a stable raw-string value in every supported document
        // schema. Strict current-schema validation applies to their owning
        // closed records, while this scalar rejects non-string representations.
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum PageRole: String, Codable, Equatable, Sendable {
    case home
    case notFound
    case standard
}

enum PageProvenance: String, Codable, Equatable, Sendable {
    case blankDefault
    case template
    case authored
    case migratedLegacy
}

enum ProjectCreationKind: String, Codable, Equatable, Sendable {
    case blank
    case template
    case migratedLegacy
}

enum NodeParent: Codable, Equatable, Sendable {
    case page(PageID)
    case node(NodeID)

    private enum CodingKeys: String, CodingKey, CaseIterable { case page, node }
    private enum PayloadKeys: String, CodingKey, CaseIterable { case _0 }

    init(from decoder: Decoder) throws {
        let strict = SiteForgeDecodingPolicy.requiresExactKeys(decoder)
        if strict { try requireExactlyOneCase(CodingKeys.self, in: decoder) }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cases = container.allKeys
        guard cases.count == 1, let key = cases.first else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Node parents require exactly one case.")
            )
        }
        let payloadDecoder = try container.superDecoder(forKey: key)
        try requireExactKeys(PayloadKeys.self, in: payloadDecoder, when: strict)
        let payload = try payloadDecoder.container(keyedBy: PayloadKeys.self)
        switch key {
        case .page: self = .page(try payload.decode(PageID.self, forKey: ._0))
        case .node: self = .node(try payload.decode(NodeID.self, forKey: ._0))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .page(let value):
            var payload = container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .page)
            try payload.encode(value, forKey: ._0)
        case .node(let value):
            var payload = container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .node)
            try payload.encode(value, forKey: ._0)
        }
    }
}

struct DocumentNode: Codable, Equatable, Identifiable, Sendable {
    let id: NodeID
    var kind: NodeKind
    var name: String
    var parent: NodeParent
    var childIDs: [NodeID]
    var properties: [NodeProperty]

    init(
        id: NodeID = NodeID(),
        kind: NodeKind,
        name: String,
        parent: NodeParent,
        childIDs: [NodeID] = [],
        properties: [NodeProperty] = []
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.parent = parent
        self.childIDs = childIDs
        self.properties = properties
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, kind, name, parent, childIDs, properties
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder, when: SiteForgeDecodingPolicy.requiresExactKeys(decoder))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(NodeID.self, forKey: .id)
        kind = try container.decode(NodeKind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        parent = try container.decode(NodeParent.self, forKey: .parent)
        childIDs = try container.decode([NodeID].self, forKey: .childIDs)
        properties = try container.decode([NodeProperty].self, forKey: .properties)
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
}

struct CanonicalImageStyle: Equatable, Sendable {
    static let namespace = "content.image.v1."
    let assetID: AssetID
    let fitMode: ImageFitMode
    let focalX: Double
    let focalY: Double
    let altText: String
    let isDecorative: Bool

    static func resolve(_ node: DocumentNode) -> CanonicalImageStyle? {
        guard node.kind == .image,
              let rawAsset = node.insertionStringProperty(namespace + "assetID"),
              let assetID = AssetID(uuidString: rawAsset),
              let rawFit = node.insertionStringProperty(namespace + "fit"),
              let fit = ImageFitMode(rawValue: rawFit),
              let focalX = node.insertionNumberProperty(namespace + "focal.x"),
              let focalY = node.insertionNumberProperty(namespace + "focal.y"),
              focalX.isFinite, focalY.isFinite,
              (0...1).contains(focalX), (0...1).contains(focalY) else { return nil }
        return CanonicalImageStyle(
            assetID: assetID,
            fitMode: fit,
            focalX: focalX,
            focalY: focalY,
            altText: node.insertionStringProperty(namespace + "alt") ?? "",
            isDecorative: node.insertionBooleanProperty(namespace + "decorative")
        )
    }
}

struct DocumentPage: Codable, Equatable, Identifiable, Sendable {
    let id: PageID
    var name: String
    var route: PageRoute
    var role: PageRole
    var provenance: PageProvenance
    var rootNodeIDs: [NodeID]
    var nodes: [DocumentNode]

    init(
        id: PageID = PageID(),
        name: String,
        route: PageRoute? = nil,
        role: PageRole = .standard,
        provenance: PageProvenance = .authored,
        rootNodeIDs: [NodeID]? = nil,
        nodes: [DocumentNode]? = nil
    ) {
        self.id = id
        self.name = name
        self.route = route ?? Self.defaultRoute(for: name)
        self.role = role
        self.provenance = provenance
        if let rootNodeIDs, let nodes {
            self.rootNodeIDs = rootNodeIDs
            self.nodes = nodes
        } else {
            let rootID = NodeID()
            self.rootNodeIDs = [rootID]
            self.nodes = [Self.minimumRoot(id: rootID, pageID: id)]
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, route, role, provenance, rootNodeIDs, nodes
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder, when: SiteForgeDecodingPolicy.requiresExactKeys(decoder))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(PageID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        route = try container.decode(PageRoute.self, forKey: .route)
        role = try container.decode(PageRole.self, forKey: .role)
        provenance = try container.decode(PageProvenance.self, forKey: .provenance)
        rootNodeIDs = try container.decode([NodeID].self, forKey: .rootNodeIDs)
        nodes = try container.decode([DocumentNode].self, forKey: .nodes)
    }

    static func minimum(
        id: PageID = PageID(),
        rootID: NodeID = NodeID(),
        name: String,
        route: String,
        role: PageRole,
        provenance: PageProvenance
    ) -> DocumentPage {
        DocumentPage(
            id: id,
            name: name,
            route: PageRoute(rawValue: route),
            role: role,
            provenance: provenance,
            rootNodeIDs: [rootID],
            nodes: [minimumRoot(id: rootID, pageID: id)]
        )
    }

    fileprivate static func deterministicUUID(namespace: UUID, label: String) -> UUID {
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

    fileprivate static func minimumRoot(id: NodeID, pageID: PageID) -> DocumentNode {
        DocumentNode(id: id, kind: .frame, name: "Root", parent: .page(pageID))
    }

    fileprivate static func defaultRoute(for name: String) -> PageRoute {
        if name.caseInsensitiveCompare("Home") == .orderedSame { return PageRoute(rawValue: "/") }
        let slug = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return PageRoute(rawValue: "/" + (slug.isEmpty ? "page" : slug))
    }
}

extension DocumentPage {
    /// The canonical ownership lists, not storage order, define authoring order.
    /// Documents are validated before adoption; this iterative walk intentionally
    /// avoids recursion for deep but valid user-authored hierarchies. It is
    /// also defensive for an in-process, not-yet-validated construction: a
    /// duplicate ID must not turn a convenience traversal into a dictionary
    /// precondition trap.
    func canonicalDepthFirstNodes() -> [DocumentNode] {
        var nodesByID: [NodeID: DocumentNode] = [:]
        nodesByID.reserveCapacity(nodes.count)
        for node in nodes where nodesByID[node.id] == nil {
            nodesByID[node.id] = node
        }
        var ordered: [DocumentNode] = []
        ordered.reserveCapacity(nodes.count)
        var visited = Set<NodeID>()
        var pending = Array(rootNodeIDs.reversed())
        while let id = pending.popLast() {
            guard visited.insert(id).inserted, let node = nodesByID[id] else { continue }
            ordered.append(node)
            pending.append(contentsOf: node.childIDs.reversed())
        }
        return ordered
    }
}

struct CanonicalDocument: Codable, Equatable, Identifiable, Sendable {
    let id: DocumentID
    var revision: UInt64
    var creationKind: ProjectCreationKind
    var templateID: TemplateID?
    var pages: [DocumentPage]
    var guides: [AuthoredGuide]
    var imageAssets: [ImageAsset]

    init(
        id: DocumentID = DocumentID(),
        revision: UInt64 = 0,
        creationKind: ProjectCreationKind = .blank,
        templateID: TemplateID? = nil,
        pages: [DocumentPage]? = nil,
        guides: [AuthoredGuide] = [],
        imageAssets: [ImageAsset] = []
    ) {
        self.id = id
        self.revision = revision
        self.creationKind = creationKind
        self.templateID = templateID
        self.pages = pages ?? BlankProjectDefaults.pages()
        self.guides = guides
        self.imageAssets = imageAssets
    }


    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, revision, creationKind, templateID, pages, guides, imageAssets
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder, when: SiteForgeDecodingPolicy.requiresExactKeys(decoder))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(DocumentID.self, forKey: .id)
        revision = try container.decode(UInt64.self, forKey: .revision)
        creationKind = try container.decode(ProjectCreationKind.self, forKey: .creationKind)
        guard container.contains(.templateID) else {
            throw DecodingError.keyNotFound(
                CodingKeys.templateID,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Current schema requires templateID, including an explicit null value."
                )
            )
        }
        templateID = try container.decodeIfPresent(TemplateID.self, forKey: .templateID)
        pages = try container.decode([DocumentPage].self, forKey: .pages)
        guides = try container.decode([AuthoredGuide].self, forKey: .guides)
        imageAssets = try container.decode([ImageAsset].self, forKey: .imageAssets)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(revision, forKey: .revision)
        try container.encode(creationKind, forKey: .creationKind)
        if let templateID {
            try container.encode(templateID, forKey: .templateID)
        } else {
            try container.encodeNil(forKey: .templateID)
        }
        try container.encode(pages, forKey: .pages)
        try container.encode(guides, forKey: .guides)
        try container.encode(imageAssets, forKey: .imageAssets)
    }
}

enum BlankProjectDefaults {
    static let requirementIDs: Set<String> = [
        "SF-0301-001", "SF-0301-002", "SF-0301-005", "SF-0301-006", "SF-0301-008",
        "SF-0303-001", "SF-0303-003", "SF-0303-005", "SF-0303-006", "SF-0303-008",
    ]
    static let homeName = "Home"
    static let homeRoute = "/"
    static let notFoundName = "Not Found"
    static let notFoundRoute = "/404"

    static func document(id: DocumentID = DocumentID()) -> CanonicalDocument {
        CanonicalDocument(id: id, creationKind: .blank, pages: pages())
    }

    static func pages(
        documentID: DocumentID? = nil,
        provenance: PageProvenance = .blankDefault
    ) -> [DocumentPage] {
        let homeID = PageID(documentID.map {
            DocumentPage.deterministicUUID(namespace: $0.rawValue, label: "default-home-page")
        } ?? UUID())
        let notFoundID = PageID(documentID.map {
            DocumentPage.deterministicUUID(namespace: $0.rawValue, label: "default-not-found-page")
        } ?? UUID())
        let homeRootID = NodeID(documentID.map {
            DocumentPage.deterministicUUID(namespace: $0.rawValue, label: "default-home-root")
        } ?? UUID())
        let notFoundRootID = NodeID(documentID.map {
            DocumentPage.deterministicUUID(namespace: $0.rawValue, label: "default-not-found-root")
        } ?? UUID())
        return [
            .minimum(
                id: homeID, rootID: homeRootID, name: homeName, route: homeRoute,
                role: .home, provenance: provenance
            ),
            .minimum(
                id: notFoundID, rootID: notFoundRootID, name: notFoundName,
                route: notFoundRoute, role: .notFound, provenance: provenance
            ),
        ]
    }
}

enum ProjectCreation {
    static func blank(id: DocumentID = DocumentID()) -> CanonicalDocument {
        BlankProjectDefaults.document(id: id)
    }

    static func template(
        id: DocumentID = DocumentID(),
        templateID: TemplateID,
        pages: [DocumentPage]
    ) -> CanonicalDocument {
        CanonicalDocument(
            id: id,
            creationKind: .template,
            templateID: templateID,
            pages: pages.map { page in
                var result = page
                result.provenance = .template
                return result
            }
        )
    }
}

enum ModelValidationError: Error, Equatable, LocalizedError {
    case revisionNotIncrementable
    case emptyPageList
    case duplicatePageID
    case duplicatePageRoute
    case invalidPageRoute
    case duplicatePageRole
    case missingPageRoot
    case invalidCreationProvenance
    case duplicateNodeID
    case duplicatePropertyID
    case duplicateGuideID
    case invalidGuidePage
    case invalidGuidePosition
    case guideLimitExceeded
    case invalidPageName
    case invalidNodeName
    case invalidPropertyKey
    case duplicatePropertyKey
    case missingNode
    case invalidParent
    case inconsistentChildren
    case duplicateChild
    case cyclicOrUnreachableTree
    case incompatibleChildOwnership
    case invalidStructuralDefaults
    case invalidFillLayerState
    case invalidBoxStyleState
    case invalidTypographyState
    case invalidResponsiveGeometryState
    case invalidResponsiveContainerState
    case invalidResponsiveVisibilityState
    case duplicateAssetID
    case duplicateAssetResourceID
    case duplicateAssetContent
    case invalidImageAsset
    case invalidImageReference

    var errorDescription: String? {
        switch self {
        case .revisionNotIncrementable: "The document revision cannot accept another transaction."
        case .emptyPageList: "A project must contain at least one page."
        case .duplicatePageID: "Page identifiers must be unique."
        case .duplicatePageRoute: "Published page routes must be unique."
        case .invalidPageRoute: "Page routes must be absolute paths without query or fragment components."
        case .duplicatePageRole: "Home and Not Found roles may each be assigned to only one page."
        case .missingPageRoot: "Every page must contain at least one valid root node."
        case .invalidCreationProvenance: "Template projects require a template identity, and blank projects cannot carry one."
        case .duplicateNodeID: "Node identifiers must be unique across the document."
        case .duplicatePropertyID: "Property identifiers must be unique across the document."
        case .duplicateGuideID: "Guide identifiers must be unique."
        case .invalidGuidePage: "Every authored guide must belong to an existing page."
        case .invalidGuidePosition: "Guide positions must be finite and within the supported canvas range."
        case .guideLimitExceeded: "This project exceeds the supported authored-guide limit."
        case .invalidPageName: "Page names cannot be empty."
        case .invalidNodeName: "Node names cannot be empty."
        case .invalidPropertyKey: "Property keys cannot be empty."
        case .duplicatePropertyKey: "A node cannot own duplicate property keys."
        case .missingNode: "A node reference does not resolve inside its owning page."
        case .invalidParent: "A node parent must belong to the same page."
        case .inconsistentChildren: "Parent and child ownership references must agree."
        case .duplicateChild: "A parent cannot contain the same child more than once."
        case .cyclicOrUnreachableTree: "The node tree must be acyclic and reachable from the page roots."
        case .incompatibleChildOwnership: "This node kind cannot own authored children."
        case .invalidStructuralDefaults: "Structural containers require their complete bounded default layout contract."
        case .invalidFillLayerState: "The document contains an invalid canonical fill-layer state."
        case .invalidBoxStyleState: "The document contains an invalid canonical border, radius, or shadow state."
        case .invalidTypographyState: "The document contains invalid canonical typography state."
        case .invalidResponsiveGeometryState: "The document contains invalid responsive geometry state."
        case .invalidResponsiveContainerState: "The document contains invalid responsive container-layout state."
        case .invalidResponsiveVisibilityState: "The document contains invalid responsive visibility state."
        case .duplicateAssetID: "Image asset identifiers must be unique."
        case .duplicateAssetResourceID: "Each image asset must own one stable project resource identity."
        case .duplicateAssetContent: "Duplicate image bytes must resolve to the existing asset identity."
        case .invalidImageAsset: "The document contains invalid image asset metadata."
        case .invalidImageReference: "An Image node must reference an existing canonical image asset."
        }
    }
}

enum CanonicalResponsiveGeometryNamespaceValidator {
    static let root = "responsive.geometry.v1."
    private static let breakpointIDs: Set<String> = [
        "60000000-0000-4000-8000-000000000002",
        "60000000-0000-4000-8000-000000000003",
    ]
    private static let fields: Set<String> = ["x", "y", "width", "height"]
    private static let supportedKinds: Set<NodeKind> = [.frame, .text, .section, .stack, .grid, .image]

    static func validate(_ node: DocumentNode) throws {
        let properties = node.properties.filter { $0.key.rawValue.hasPrefix(root) }
        guard !properties.isEmpty else { return }
        guard supportedKinds.contains(node.kind) else { throw ModelValidationError.invalidResponsiveGeometryState }
        for property in properties {
            let suffix = String(property.key.rawValue.dropFirst(root.count))
            let components = suffix.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard components.count == 2, breakpointIDs.contains(components[0]), fields.contains(components[1]),
                  case .number(let value) = property.value, value.isFinite,
                  abs(value) <= 1_000_000_000,
                  !(["width", "height"].contains(components[1])) || value >= 1 else {
                throw ModelValidationError.invalidResponsiveGeometryState
            }
        }
    }
}

enum CanonicalResponsiveContainerNamespaceValidator {
    static let root = "responsive.container.v1."
    private static let breakpointIDs: Set<String> = [
        "60000000-0000-4000-8000-000000000002", "60000000-0000-4000-8000-000000000003",
    ]

    static func validate(_ node: DocumentNode) throws {
        let properties = node.properties.filter { $0.key.rawValue.hasPrefix(root) }
        guard !properties.isEmpty else { return }
        guard [.section, .stack, .grid].contains(node.kind) else { throw ModelValidationError.invalidResponsiveContainerState }
        for property in properties {
            let components = String(property.key.rawValue.dropFirst(root.count)).split(separator: ".").map(String.init)
            guard components.count == 2, breakpointIDs.contains(components[0]),
                  validates(field: components[1], value: property.value, kind: node.kind) else {
                throw ModelValidationError.invalidResponsiveContainerState
            }
        }
    }

    /// Canonical decoding owns its wire-domain validation and deliberately
    /// does not depend on Inspector command types. Keep these bounds in sync
    /// with the typed authoring registry; the headless model remains usable by
    /// package, recovery, and migration code without importing editor policy.
    private static func validates(field: String, value: PropertyValue, kind: NodeKind) -> Bool {
        let supported: Bool = switch (kind, field) {
        case (.section, "padding"): true
        case (.stack, "padding"), (.stack, "gap"), (.stack, "axis"), (.stack, "alignment"): true
        case (.grid, "padding"), (.grid, "gap"), (.grid, "columns"): true
        default: false
        }
        guard supported else { return false }
        switch (field, value) {
        case ("padding", .number(let number)), ("gap", .number(let number)):
            return number.isFinite && (0...10_000).contains(number)
        case ("columns", .number(let number)):
            return number.isFinite && number.rounded(.towardZero) == number && (1...64).contains(number)
        case ("axis", .string(let value)):
            return ["vertical", "horizontal"].contains(value)
        case ("alignment", .string(let value)):
            return ["start", "center", "end", "stretch"].contains(value)
        default:
            return false
        }
    }
}

enum CanonicalResponsiveVisibilityNamespaceValidator {
    static let root = "responsive.visibility.v1."
    private static let breakpointIDs: Set<String> = [
        "60000000-0000-4000-8000-000000000002", "60000000-0000-4000-8000-000000000003",
    ]

    static func validate(_ node: DocumentNode) throws {
        let properties = node.properties.filter { $0.key.rawValue.hasPrefix(root) }
        guard !properties.isEmpty else { return }
        guard [.frame, .text, .section, .stack, .grid].contains(node.kind) else {
            throw ModelValidationError.invalidResponsiveVisibilityState
        }
        for property in properties {
            let components = String(property.key.rawValue.dropFirst(root.count)).split(separator: ".").map(String.init)
            guard components.count == 2, breakpointIDs.contains(components[0]), components[1] == "visible",
                  case .boolean = property.value else { throw ModelValidationError.invalidResponsiveVisibilityState }
        }
    }
}

/// SF-0506-001/004 — strict headless validation for the bounded v1 box-style
/// namespace. Partial components and unknown keys are rejected before package
/// adoption; absence remains the deterministic default.
enum CanonicalBoxStyleNamespaceValidator {
    static let root = "style.box.v1."
    private static let supportedKinds: Set<NodeKind> = [.frame, .section, .stack, .grid]
    private static let borderKeys: Set<String> = [
        "border.width", "border.style", "border.color.red", "border.color.green",
        "border.color.blue", "border.color.alpha",
    ]
    private static let shadowKeys: Set<String> = [
        "shadow.offsetX", "shadow.offsetY", "shadow.blur", "shadow.spread",
        "shadow.color.red", "shadow.color.green", "shadow.color.blue", "shadow.color.alpha",
    ]
    private static let radiusKey = "radius.uniform"

    static func validate(_ node: DocumentNode) throws {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix(root) }
        guard !owned.isEmpty else { return }
        guard supportedKinds.contains(node.kind) else { throw ModelValidationError.invalidBoxStyleState }
        let suffixes = owned.map { String($0.key.rawValue.dropFirst(root.count)) }
        guard Set(suffixes).count == suffixes.count else { throw ModelValidationError.invalidBoxStyleState }
        let allowed = borderKeys.union(shadowKeys).union([radiusKey])
        guard Set(suffixes).isSubset(of: allowed) else { throw ModelValidationError.invalidBoxStyleState }
        let values = Dictionary(uniqueKeysWithValues: owned.map { (String($0.key.rawValue.dropFirst(root.count)), $0.value) })
        if !borderKeys.isDisjoint(with: suffixes) {
            guard borderKeys.isSubset(of: suffixes), case .number(let width)? = values["border.width"],
                  width.isFinite, width > 0, width <= 100, case .string(let style)? = values["border.style"],
                  ["solid", "dashed", "dotted"].contains(style) else { throw ModelValidationError.invalidBoxStyleState }
            try validateColor("border.color", values: values)
        }
        if let value = values[radiusKey] {
            guard case .number(let radius) = value, radius.isFinite, (0...10_000).contains(radius) else { throw ModelValidationError.invalidBoxStyleState }
        }
        if !shadowKeys.isDisjoint(with: suffixes) {
            guard shadowKeys.isSubset(of: suffixes) else { throw ModelValidationError.invalidBoxStyleState }
            for key in ["shadow.offsetX", "shadow.offsetY", "shadow.blur", "shadow.spread"] {
                guard case .number(let value)? = values[key], value.isFinite else { throw ModelValidationError.invalidBoxStyleState }
            }
            guard case .number(let x)? = values["shadow.offsetX"], (-10_000...10_000).contains(x),
                  case .number(let y)? = values["shadow.offsetY"], (-10_000...10_000).contains(y),
                  case .number(let blur)? = values["shadow.blur"], (0...1_000).contains(blur),
                  case .number(let spread)? = values["shadow.spread"], (-1_000...1_000).contains(spread) else {
                throw ModelValidationError.invalidBoxStyleState
            }
            try validateColor("shadow.color", values: values)
        }
    }

    private static func validateColor(_ prefix: String, values: [String: PropertyValue]) throws {
        for channel in ["red", "green", "blue", "alpha"] {
            guard case .number(let value)? = values["\(prefix).\(channel)"], value.isFinite, (0...1).contains(value) else {
                throw ModelValidationError.invalidBoxStyleState
            }
        }
    }
}

enum CanonicalTypographyNamespaceValidator {
    static let root = CanonicalTypography.namespace
    static func validate(_ node: DocumentNode) throws {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix(root) }
        guard !owned.isEmpty else { return }
        guard node.kind == .text else { throw ModelValidationError.invalidTypographyState }
        let suffixes = owned.map { String($0.key.rawValue.dropFirst(root.count)) }
        let allowed: Set<String> = ["family", "weight", "size", "lineHeight", "tracking", "alignment"]
        guard Set(suffixes).count == suffixes.count, Set(suffixes).isSubset(of: allowed) else {
            throw ModelValidationError.invalidTypographyState
        }
        let values = Dictionary(uniqueKeysWithValues: owned.map { (String($0.key.rawValue.dropFirst(root.count)), $0.value) })
        if case .string(let family)? = values["family"] {
            guard !family.isEmpty,
                  family == family.trimmingCharacters(in: .whitespacesAndNewlines),
                  family.utf8.count <= 128,
                  family.rangeOfCharacter(from: .controlCharacters) == nil else {
                throw ModelValidationError.invalidTypographyState
            }
        } else if values["family"] != nil { throw ModelValidationError.invalidTypographyState }
        if case .string(let weight)? = values["weight"] {
            guard CanonicalFontWeight(rawValue: weight) != nil else { throw ModelValidationError.invalidTypographyState }
        } else if values["weight"] != nil { throw ModelValidationError.invalidTypographyState }
        if case .string(let alignment)? = values["alignment"] {
            guard CanonicalTextAlignment(rawValue: alignment) != nil else { throw ModelValidationError.invalidTypographyState }
        } else if values["alignment"] != nil { throw ModelValidationError.invalidTypographyState }
        for key in ["size", "lineHeight", "tracking"] where values[key] != nil {
            guard case .number(let number)? = values[key], number.isFinite else { throw ModelValidationError.invalidTypographyState }
            switch key {
            case "size": guard (1...1_000).contains(number) else { throw ModelValidationError.invalidTypographyState }
            case "lineHeight": guard (1...2_000).contains(number) else { throw ModelValidationError.invalidTypographyState }
            default: guard (-100...100).contains(number) else { throw ModelValidationError.invalidTypographyState }
            }
        }
        let fallback = CanonicalTypography.defaultValue
        let typography = CanonicalTypography(
            family: { if case .string(let value)? = values["family"] { value } else { fallback.family } }(),
            weight: { if case .string(let value)? = values["weight"] { CanonicalFontWeight(rawValue: value) ?? fallback.weight } else { fallback.weight } }(),
            size: { if case .number(let value)? = values["size"] { value } else { fallback.size } }(),
            lineHeight: { if case .number(let value)? = values["lineHeight"] { value } else { fallback.lineHeight } }(),
            tracking: { if case .number(let value)? = values["tracking"] { value } else { fallback.tracking } }(),
            alignment: { if case .string(let value)? = values["alignment"] { CanonicalTextAlignment(rawValue: value) ?? fallback.alignment } else { fallback.alignment } }()
        )
        guard typography.isValid else { throw ModelValidationError.invalidTypographyState }
    }
}

enum CanonicalImageNamespaceValidator {
    static let root = "content.image.v1."
    private static let required: Set<String> = [
        "assetID", "fit", "focal.x", "focal.y", "alt", "decorative",
    ]

    static func validate(_ node: DocumentNode) throws {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix(root) }
        guard !owned.isEmpty else { return }
        guard node.kind == .image else { throw ModelValidationError.invalidImageReference }
        let suffixes = owned.map { String($0.key.rawValue.dropFirst(root.count)) }
        guard Set(suffixes) == required, suffixes.count == required.count else {
            throw ModelValidationError.invalidImageReference
        }
        let values = Dictionary(uniqueKeysWithValues: owned.map {
            (String($0.key.rawValue.dropFirst(root.count)), $0.value)
        })
        guard case .string(let asset)? = values["assetID"], AssetID(uuidString: asset) != nil,
              case .string(let fit)? = values["fit"], ImageFitMode(rawValue: fit) != nil,
              case .number(let x)? = values["focal.x"], x.isFinite, (0...1).contains(x),
              case .number(let y)? = values["focal.y"], y.isFinite, (0...1).contains(y),
              case .string(let alt)? = values["alt"], alt.utf8.count <= 4_096,
              !alt.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t"
              }),
              case .boolean? = values["decorative"] else {
            throw ModelValidationError.invalidImageReference
        }
    }
}

/// Headless canonical validation for the versioned fill-layer namespace.
///
/// The richer typed projection lives in `TransformModel`, but document
/// validity cannot depend on that downstream authoring module. This validator
/// therefore enforces the persisted namespace contract using only canonical
/// `DocumentNode`/`PropertyValue` types, keeping the smallest model compile
/// boundary independently usable by migration and architecture checks.
enum CanonicalFillLayerNamespaceValidator {
    static let root = "style.fill.layers.v1"
    static let orderKey = "style.fill.layers.v1.order"
    private static let supportedKinds: Set<NodeKind> = [.frame, .section, .stack, .grid]

    static func validate(_ node: DocumentNode) throws {
        let owned = node.properties.filter { owns($0.key.rawValue) }
        guard !owned.isEmpty else { return }
        guard supportedKinds.contains(node.kind) else { throw ModelValidationError.invalidFillLayerState }

        let keys = owned.map(\.key.rawValue)
        guard Set(keys).count == keys.count else { throw ModelValidationError.invalidFillLayerState }
        let values = Dictionary(uniqueKeysWithValues: owned.map { ($0.key.rawValue, $0.value) })
        guard case .string(let order)? = values[orderKey] else {
            throw ModelValidationError.invalidFillLayerState
        }
        let layerIDs = try identifiers(order, allowsEmpty: true)
        guard Set(layerIDs).count == layerIDs.count else {
            throw ModelValidationError.invalidFillLayerState
        }

        var expected: Set<String> = [orderKey]
        for layerID in layerIDs {
            let prefix = "\(root).\(layerID)"
            let kindKey = "\(prefix).kind"
            let enabledKey = "\(prefix).enabled"
            expected.formUnion([kindKey, enabledKey])
            guard case .string(let kind)? = values[kindKey],
                  case .boolean? = values[enabledKey] else {
                throw ModelValidationError.invalidFillLayerState
            }
            switch kind {
            case "solid":
                try validateColor(prefix: prefix, values: values, expected: &expected)
            case "linearGradient":
                let angleKey = "\(prefix).angle"
                let stopsKey = "\(prefix).stops"
                expected.formUnion([angleKey, stopsKey])
                guard case .number(let angle)? = values[angleKey],
                      angle.isFinite, (0..<360).contains(angle),
                      case .string(let stopOrder)? = values[stopsKey] else {
                    throw ModelValidationError.invalidFillLayerState
                }
                let stopIDs = try identifiers(stopOrder, allowsEmpty: false)
                guard stopIDs.count >= 2, Set(stopIDs).count == stopIDs.count else {
                    throw ModelValidationError.invalidFillLayerState
                }
                for stopID in stopIDs {
                    let stopPrefix = "\(prefix).stop.\(stopID)"
                    let positionKey = "\(stopPrefix).position"
                    expected.insert(positionKey)
                    guard case .number(let position)? = values[positionKey],
                          position.isFinite, (0...1).contains(position) else {
                        throw ModelValidationError.invalidFillLayerState
                    }
                    try validateColor(prefix: stopPrefix, values: values, expected: &expected)
                }
            default:
                throw ModelValidationError.invalidFillLayerState
            }
        }
        guard Set(keys) == expected else { throw ModelValidationError.invalidFillLayerState }
    }

    private static func validateColor(
        prefix: String,
        values: [String: PropertyValue],
        expected: inout Set<String>
    ) throws {
        for channel in ["red", "green", "blue", "alpha"] {
            let key = "\(prefix).\(channel)"
            expected.insert(key)
            guard case .number(let value)? = values[key],
                  value.isFinite, (0...1).contains(value) else {
                throw ModelValidationError.invalidFillLayerState
            }
        }
    }

    private static func identifiers(_ value: String, allowsEmpty: Bool) throws -> [String] {
        if value.isEmpty, allowsEmpty { return [] }
        let tokens = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard !tokens.isEmpty, tokens.allSatisfy({ token in
            guard !token.isEmpty, let identifier = UUID(uuidString: token) else { return false }
            return identifier.uuidString.lowercased() == token
        }) else {
            throw ModelValidationError.invalidFillLayerState
        }
        return tokens
    }

    private static func owns(_ key: String) -> Bool {
        key == root || key.hasPrefix("\(root).")
    }
}

extension CanonicalDocument {
    func validated() throws -> CanonicalDocument {
        try validate()
        return self
    }

    func validate(checkpoint: () throws -> Void = {}) throws {
        try checkpoint()
        guard revision < UInt64.max else { throw ModelValidationError.revisionNotIncrementable }
        guard !pages.isEmpty else { throw ModelValidationError.emptyPageList }
        guard Set(pages.map(\.id)).count == pages.count else {
            throw ModelValidationError.duplicatePageID
        }
        guard Set(pages.map(\.route)).count == pages.count else {
            throw ModelValidationError.duplicatePageRoute
        }
        let specialRoles = pages.map(\.role).filter { $0 != .standard }
        guard Set(specialRoles).count == specialRoles.count else {
            throw ModelValidationError.duplicatePageRole
        }
        switch creationKind {
        case .template:
            guard templateID != nil else { throw ModelValidationError.invalidCreationProvenance }
        case .blank, .migratedLegacy:
            guard templateID == nil else { throw ModelValidationError.invalidCreationProvenance }
        }

        guard imageAssets.count <= ImageAsset.maximumAssetCount else {
            throw ModelValidationError.invalidImageAsset
        }
        guard Set(imageAssets.map(\.id)).count == imageAssets.count else {
            throw ModelValidationError.duplicateAssetID
        }
        guard Set(imageAssets.map(\.resourceID)).count == imageAssets.count else {
            throw ModelValidationError.duplicateAssetResourceID
        }
        guard Set(imageAssets.map(\.contentHash)).count == imageAssets.count else {
            throw ModelValidationError.duplicateAssetContent
        }
        for asset in imageAssets {
            do { try asset.validate() }
            catch { throw ModelValidationError.invalidImageAsset }
        }
        let assetIDs = Set(imageAssets.map(\.id))

        var documentNodeIDs = Set<NodeID>()
        var documentPropertyIDs = Set<PropertyID>()
        for page in pages {
            try checkpoint()
            try page.validate(
                documentNodeIDs: &documentNodeIDs,
                documentPropertyIDs: &documentPropertyIDs,
                assetIDs: assetIDs,
                checkpoint: checkpoint
            )
        }
        guard guides.count <= 10_000 else { throw ModelValidationError.guideLimitExceeded }
        guard Set(guides.map(\.id)).count == guides.count else {
            throw ModelValidationError.duplicateGuideID
        }
        let pageIDs = Set(pages.map(\.id))
        for guide in guides {
            try checkpoint()
            guard pageIDs.contains(guide.pageID) else {
                throw ModelValidationError.invalidGuidePage
            }
            guard guide.position.isFinite,
                  abs(guide.position) <= AuthoredGuide.maximumCoordinate else {
                throw ModelValidationError.invalidGuidePosition
            }
        }
    }
}

private extension DocumentPage {
    func validate(
        documentNodeIDs: inout Set<NodeID>,
        documentPropertyIDs: inout Set<PropertyID>,
        assetIDs: Set<AssetID>,
        checkpoint: () throws -> Void
    ) throws {
        try checkpoint()
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModelValidationError.invalidPageName
        }
        let routeValue = route.rawValue
        guard routeValue.first == "/", !routeValue.contains("?"), !routeValue.contains("#"),
              !routeValue.contains("//"),
              routeValue == "/" || !routeValue.hasSuffix("/") else {
            throw ModelValidationError.invalidPageRoute
        }
        guard !rootNodeIDs.isEmpty, !nodes.isEmpty else {
            throw ModelValidationError.missingPageRoot
        }

        let nodeIDs = Set(nodes.map(\.id))
        guard nodeIDs.count == nodes.count else { throw ModelValidationError.duplicateNodeID }
        guard documentNodeIDs.isDisjoint(with: nodeIDs) else {
            throw ModelValidationError.duplicateNodeID
        }
        documentNodeIDs.formUnion(nodeIDs)

        guard Set(rootNodeIDs).count == rootNodeIDs.count else {
            throw ModelValidationError.duplicateChild
        }

        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let childrenByParent = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, Set($0.childIDs)) })
        for rootID in rootNodeIDs {
            try checkpoint()
            guard let root = nodesByID[rootID] else { throw ModelValidationError.missingNode }
            guard root.parent == .page(id) else { throw ModelValidationError.invalidParent }
        }

        let declaredRoots = Set(nodes.compactMap { node -> NodeID? in
            guard case .page(let pageID) = node.parent, pageID == id else { return nil }
            return node.id
        })
        guard declaredRoots == Set(rootNodeIDs) else { throw ModelValidationError.invalidParent }

        for node in nodes {
            try checkpoint()
            guard !node.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ModelValidationError.invalidNodeName
            }
            guard Set(node.childIDs).count == node.childIDs.count else {
                throw ModelValidationError.duplicateChild
            }
            guard node.childIDs.isEmpty || node.kind.acceptsAuthoredChildren else {
                throw ModelValidationError.incompatibleChildOwnership
            }

            switch node.parent {
            case .page(let pageID):
                guard pageID == id else { throw ModelValidationError.invalidParent }
            case .node(let parentID):
                guard nodesByID[parentID] != nil else { throw ModelValidationError.invalidParent }
                guard childrenByParent[parentID]?.contains(node.id) == true else {
                    throw ModelValidationError.inconsistentChildren
                }
            }

            for childID in node.childIDs {
                try checkpoint()
                guard let child = nodesByID[childID] else { throw ModelValidationError.missingNode }
                guard child.parent == .node(node.id) else {
                    throw ModelValidationError.inconsistentChildren
                }
            }

            let propertyIDs = Set(node.properties.map(\.id))
            guard propertyIDs.count == node.properties.count else {
                throw ModelValidationError.duplicatePropertyID
            }
            guard documentPropertyIDs.isDisjoint(with: propertyIDs) else {
                throw ModelValidationError.duplicatePropertyID
            }
            documentPropertyIDs.formUnion(propertyIDs)

            let keys = node.properties.map(\.key.rawValue)
            guard keys.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw ModelValidationError.invalidPropertyKey
            }
            guard Set(keys).count == keys.count else {
                throw ModelValidationError.duplicatePropertyKey
            }
            try CanonicalFillLayerNamespaceValidator.validate(node)
            try CanonicalBoxStyleNamespaceValidator.validate(node)
            try CanonicalTypographyNamespaceValidator.validate(node)
            try CanonicalImageNamespaceValidator.validate(node)
            try CanonicalResponsiveGeometryNamespaceValidator.validate(node)
            try CanonicalResponsiveContainerNamespaceValidator.validate(node)
            try CanonicalResponsiveVisibilityNamespaceValidator.validate(node)
            if node.kind == .image {
                guard let reference = node.insertionStringProperty(CanonicalImageStyle.namespace + "assetID"),
                      let assetID = AssetID(uuidString: reference), assetIDs.contains(assetID),
                      let fit = node.insertionStringProperty(CanonicalImageStyle.namespace + "fit"),
                      ImageFitMode(rawValue: fit) != nil,
                      let focalX = node.insertionNumberProperty(CanonicalImageStyle.namespace + "focal.x"),
                      let focalY = node.insertionNumberProperty(CanonicalImageStyle.namespace + "focal.y"),
                      (0...1).contains(focalX), (0...1).contains(focalY),
                      focalX.isFinite, focalY.isFinite,
                      node.insertionBooleanProperty(CanonicalImageStyle.namespace + "decorative")
                        || node.insertionStringProperty(CanonicalImageStyle.namespace + "alt") != nil else {
                    throw ModelValidationError.invalidImageReference
                }
            }
            try node.validateStructuralDefaults()
        }

        var visited = Set<NodeID>()
        var pending = Array(rootNodeIDs.reversed())
        while let nodeID = pending.popLast() {
            try checkpoint()
            guard visited.insert(nodeID).inserted else {
                throw ModelValidationError.cyclicOrUnreachableTree
            }
            guard let node = nodesByID[nodeID] else { throw ModelValidationError.missingNode }
            pending.append(contentsOf: node.childIDs.reversed())
        }
        guard visited == nodeIDs else { throw ModelValidationError.cyclicOrUnreachableTree }
    }
}

private extension DocumentNode {
    func validateStructuralDefaults() throws {
        let propertiesByKey = Dictionary(uniqueKeysWithValues: properties.map { ($0.key.rawValue, $0) })
        func numberValue(_ key: String) -> Double? {
            guard let property = propertiesByKey[key], case .number(let value) = property.value else { return nil }
            return value
        }
        func number(_ key: String, range: ClosedRange<Double>) -> Bool {
            guard let value = numberValue(key) else { return false }
            return value.isFinite && range.contains(value)
        }
        func string(_ key: String, equals expected: String) -> Bool {
            guard let property = propertiesByKey[key], case .string(let value) = property.value else { return false }
            return value == expected
        }
        func string(_ key: String, allowed: Set<String>) -> Bool {
            guard let property = propertiesByKey[key], case .string(let value) = property.value else { return false }
            return allowed.contains(value)
        }
        switch kind {
        case .section:
            guard string("layout.container.kind", equals: "section"),
                  number("layout.padding", range: 0...10_000),
                  string("layout.axis", equals: "vertical") else {
                throw ModelValidationError.invalidStructuralDefaults
            }
        case .stack:
            guard string("layout.container.kind", equals: "stack"),
                  string("layout.axis", allowed: ["vertical", "horizontal"]),
                  number("layout.padding", range: 0...10_000),
                  number("layout.gap", range: 0...10_000),
                  string("layout.align", allowed: ["start", "center", "end", "stretch"]) else {
                throw ModelValidationError.invalidStructuralDefaults
            }
        case .grid:
            guard string("layout.container.kind", equals: "grid"),
                  number("layout.padding", range: 0...10_000),
                  number("layout.gap", range: 0...10_000),
                  number("layout.grid.columns", range: 1...64),
                  numberValue("layout.grid.columns")?.rounded(.towardZero)
                    == numberValue("layout.grid.columns"),
                  string("layout.grid.placement", equals: "row-major") else {
                throw ModelValidationError.invalidStructuralDefaults
            }
        case .frame, .text, .image, .component: break
        }
    }
}

enum DocumentSerializationError: Error, Equatable, LocalizedError {
    case malformedInput
    case unsupportedSchema(Int)
    case invalidModel(ModelValidationError)

    var errorDescription: String? {
        switch self {
        case .malformedInput: "The document data is malformed."
        case .unsupportedSchema(let version): "Schema version \(version) is not supported."
        case .invalidModel(let error): error.localizedDescription
        }
    }
}

enum DocumentSerializer {
    // Schema 5 adds the canonical image-asset catalogue and versioned Image
    // reference namespace. Schema 4 remains an immutable historical shape and
    // is re-emitted as v5 on the next deterministic save.
    static let currentSchemaVersion = 5
    static let minimumSupportedSchemaVersion = 1

    private struct SchemaHeader: Decodable {
        let schemaVersion: Int
    }

    private struct CurrentEnvelope: Codable {
        let schemaVersion: Int
        let document: CanonicalDocument

        private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, document }

        init(schemaVersion: Int, document: CanonicalDocument) {
            self.schemaVersion = schemaVersion
            self.document = document
        }

        init(from decoder: Decoder) throws {
            try requireExactKeys(CodingKeys.self, in: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            document = try container.decode(CanonicalDocument.self, forKey: .document)
        }
    }

    private struct SchemaOneEnvelope: Decodable {
        let schemaVersion: Int
        let document: SchemaOneDocument

        private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, document }

        init(from decoder: Decoder) throws {
            try requireExactKeys(CodingKeys.self, in: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            document = try container.decode(SchemaOneDocument.self, forKey: .document)
        }
    }

    private struct SchemaTwoEnvelope: Decodable {
        let schemaVersion: Int
        let document: SchemaTwoDocument

        private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, document }

        init(from decoder: Decoder) throws {
            try requireExactKeys(CodingKeys.self, in: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            document = try container.decode(SchemaTwoDocument.self, forKey: .document)
        }
    }

    private struct SchemaThreeEnvelope: Decodable {
        let schemaVersion: Int
        let document: SchemaFourDocument

        private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, document }

        init(from decoder: Decoder) throws {
            try requireExactKeys(CodingKeys.self, in: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            document = try container.decode(SchemaFourDocument.self, forKey: .document)
        }
    }

    private struct SchemaFourEnvelope: Decodable {
        let schemaVersion: Int
        let document: SchemaFourDocument
        private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, document }
        init(from decoder: Decoder) throws {
            try requireExactKeys(CodingKeys.self, in: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            document = try container.decode(SchemaFourDocument.self, forKey: .document)
        }
    }

    private struct SchemaFourDocument: Decodable {
        let id: DocumentID
        let revision: UInt64
        let creationKind: ProjectCreationKind
        let templateID: TemplateID?
        let pages: [DocumentPage]
        let guides: [AuthoredGuide]
        private enum CodingKeys: String, CodingKey, CaseIterable {
            case id, revision, creationKind, templateID, pages, guides
        }
        init(from decoder: Decoder) throws {
            try requireExactKeys(CodingKeys.self, in: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(DocumentID.self, forKey: .id)
            revision = try container.decode(UInt64.self, forKey: .revision)
            creationKind = try container.decode(ProjectCreationKind.self, forKey: .creationKind)
            guard container.contains(.templateID) else {
                throw DecodingError.keyNotFound(CodingKeys.templateID, .init(codingPath: decoder.codingPath, debugDescription: "Schema 4 requires templateID."))
            }
            templateID = try container.decodeIfPresent(TemplateID.self, forKey: .templateID)
            pages = try container.decode([DocumentPage].self, forKey: .pages)
            guides = try container.decode([AuthoredGuide].self, forKey: .guides)
        }
        func migrated() -> CanonicalDocument {
            CanonicalDocument(id: id, revision: revision, creationKind: creationKind,
                              templateID: templateID, pages: pages, guides: guides, imageAssets: [])
        }
    }

    private struct SchemaTwoDocument: Decodable {
        let id: DocumentID
        let revision: UInt64
        let creationKind: ProjectCreationKind
        let templateID: TemplateID?
        let pages: [DocumentPage]

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case id, revision, creationKind, templateID, pages
        }

        init(from decoder: Decoder) throws {
            try requireExactKeys(CodingKeys.self, in: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(DocumentID.self, forKey: .id)
            revision = try container.decode(UInt64.self, forKey: .revision)
            creationKind = try container.decode(ProjectCreationKind.self, forKey: .creationKind)
            guard container.contains(.templateID) else {
                throw DecodingError.keyNotFound(
                    CodingKeys.templateID,
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Schema 2 requires an explicit templateID value."
                    )
                )
            }
            templateID = try container.decodeIfPresent(TemplateID.self, forKey: .templateID)
            pages = try container.decode([DocumentPage].self, forKey: .pages)
        }

        func migrated() -> CanonicalDocument {
            CanonicalDocument(
                id: id,
                revision: revision,
                creationKind: creationKind,
                templateID: templateID,
                pages: pages,
                guides: []
            )
        }
    }

    private struct SchemaOneDocument: Decodable {
        let id: DocumentID
        let revision: UInt64
        let pages: [SchemaOnePage]

        private enum CodingKeys: String, CodingKey, CaseIterable { case id, revision, pages }

        init(from decoder: Decoder) throws {
            // Schema 1 allowed an explicitly empty page *list* while it was
            // being normalized into the blank-project baseline. It did not
            // allow the ownership collection itself to be omitted: accepting
            // that would turn a truncated package into a new blank project.
            // Reject future keys and require the original collection field.
            try requireKnownKeys(CodingKeys.self, in: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(DocumentID.self, forKey: .id)
            revision = try container.decode(UInt64.self, forKey: .revision)
            pages = try container.decode([SchemaOnePage].self, forKey: .pages)
        }

        func migrated() -> CanonicalDocument {
            let migratedPages = pages.isEmpty
                ? BlankProjectDefaults.pages(documentID: id, provenance: .migratedLegacy)
                : pages.map { $0.migrated() }
            return CanonicalDocument(
                id: id,
                revision: revision,
                creationKind: .migratedLegacy,
                templateID: nil,
                pages: migratedPages
            )
        }
    }

    private struct SchemaOnePage: Decodable {
        let id: PageID
        let name: String
        let rootNodeIDs: [NodeID]
        let nodes: [DocumentNode]

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case id, name, rootNodeIDs, nodes
        }

        init(from decoder: Decoder) throws {
            try requireKnownKeys(CodingKeys.self, in: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(PageID.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            rootNodeIDs = try container.decodeIfPresent([NodeID].self, forKey: .rootNodeIDs) ?? []
            nodes = try container.decodeIfPresent([DocumentNode].self, forKey: .nodes) ?? []
        }

        func migrated() -> DocumentPage {
            let route = DocumentPage.defaultRoute(for: name)
            let role: PageRole = route.rawValue == "/" ? .home : .standard
            if rootNodeIDs.isEmpty && nodes.isEmpty {
                let rootID = NodeID(DocumentPage.deterministicUUID(
                    namespace: id.rawValue,
                    label: "minimum-root"
                ))
                return .minimum(
                    id: id,
                    rootID: rootID,
                    name: name,
                    route: route.rawValue,
                    role: role,
                    provenance: .migratedLegacy
                )
            }
            return DocumentPage(
                id: id,
                name: name,
                route: route,
                role: role,
                provenance: .migratedLegacy,
                rootNodeIDs: rootNodeIDs,
                nodes: nodes
            )
        }
    }

    static func encode(_ document: CanonicalDocument) throws -> Data {
        do {
            try document.validate()
        } catch let error as ModelValidationError {
            throw DocumentSerializationError.invalidModel(error)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(
            CurrentEnvelope(schemaVersion: currentSchemaVersion, document: document)
        )
    }

    static func decode(_ data: Data, checkpoint: () throws -> Void = {}) throws -> CanonicalDocument {
        try checkpoint()
        let decoder = JSONDecoder()
        let header: SchemaHeader
        do {
            header = try decoder.decode(SchemaHeader.self, from: data)
        } catch {
            throw DocumentSerializationError.malformedInput
        }
        try checkpoint()
        guard (minimumSupportedSchemaVersion...currentSchemaVersion).contains(header.schemaVersion) else {
            throw DocumentSerializationError.unsupportedSchema(header.schemaVersion)
        }

        let document: CanonicalDocument
        switch header.schemaVersion {
        case 1:
            do {
                let historicalDecoder = JSONDecoder()
                historicalDecoder.userInfo[SiteForgeDecodingPolicy.strictCurrentSchema] = true
                document = try historicalDecoder.decode(SchemaOneEnvelope.self, from: data).document.migrated()
            } catch {
                throw DocumentSerializationError.malformedInput
            }
        case 2:
            do {
                let historicalDecoder = JSONDecoder()
                historicalDecoder.userInfo[SiteForgeDecodingPolicy.strictCurrentSchema] = true
                document = try historicalDecoder.decode(SchemaTwoEnvelope.self, from: data).document.migrated()
            } catch {
                throw DocumentSerializationError.malformedInput
            }
        case 3:
            do {
                let historicalDecoder = JSONDecoder()
                historicalDecoder.userInfo[SiteForgeDecodingPolicy.strictCurrentSchema] = true
                document = try historicalDecoder.decode(SchemaThreeEnvelope.self, from: data).document.migrated()
            } catch {
                throw DocumentSerializationError.malformedInput
            }
        case 4:
            do {
                let historicalDecoder = JSONDecoder()
                historicalDecoder.userInfo[SiteForgeDecodingPolicy.strictCurrentSchema] = true
                document = try historicalDecoder.decode(SchemaFourEnvelope.self, from: data).document.migrated()
            } catch {
                throw DocumentSerializationError.malformedInput
            }
        case currentSchemaVersion:
            do {
                let strictDecoder = JSONDecoder()
                strictDecoder.userInfo[SiteForgeDecodingPolicy.strictCurrentSchema] = true
                document = try strictDecoder.decode(CurrentEnvelope.self, from: data).document
            } catch {
                throw DocumentSerializationError.malformedInput
            }
        default:
            throw DocumentSerializationError.unsupportedSchema(header.schemaVersion)
        }
        try checkpoint()
        do {
            try document.validate(checkpoint: checkpoint)
        } catch let error as ModelValidationError {
            throw DocumentSerializationError.invalidModel(error)
        }
        return document
    }

    static func schemaVersion(in data: Data) throws -> Int {
        do {
            return try JSONDecoder().decode(SchemaHeader.self, from: data).schemaVersion
        } catch {
            throw DocumentSerializationError.malformedInput
        }
    }
}
