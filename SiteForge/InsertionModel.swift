import CryptoKit
import Foundation

/// Shared responsive fields live below the transform/Inspector boundary so
/// canonical insertion/layout resolution can remain a standalone headless
/// subsystem. Inspector registries consume these types; they do not own them.
enum GeometryInspectorField: String, CaseIterable, Hashable, Sendable {
    case x, y, width, height

    var title: String {
        switch self { case .x: "X"; case .y: "Y"; case .width: "Width"; case .height: "Height" }
    }
    var propertyKey: String { "layout.\(rawValue)" }
    var requiresPositiveValue: Bool { self == .width || self == .height }
}

enum ResponsiveBreakpointIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "responsive-breakpoint"
}
typealias BreakpointID = StableIdentifier<ResponsiveBreakpointIdentifierDomain>

/// Product-owned v1 breakpoints. Scene selection stays noncanonical.
enum ResponsiveBreakpoint: String, CaseIterable, Codable, Sendable {
    case desktop, tablet, mobile

    var id: BreakpointID {
        let raw: String = switch self {
        case .desktop: "60000000-0000-4000-8000-000000000001"
        case .tablet: "60000000-0000-4000-8000-000000000002"
        case .mobile: "60000000-0000-4000-8000-000000000003"
        }
        return BreakpointID(UUID(uuidString: raw)!)
    }
    var title: String { rawValue.capitalized }
    var rangeDescription: String {
        switch self { case .desktop: "1024 points and wider"; case .tablet: "600–1023 points"; case .mobile: "below 600 points" }
    }
    static func resolving(width: Double) -> ResponsiveBreakpoint {
        guard width.isFinite else { return .desktop }
        if width < 600 { return .mobile }
        if width < 1024 { return .tablet }
        return .desktop
    }
}

enum ResponsiveGeometrySource: Equatable, Sendable {
    case baseDesktop
    case override(ResponsiveBreakpoint)

    var label: String {
        switch self { case .baseDesktop: "Inherited from Desktop"; case .override(let value): "Authored for \(value.title)" }
    }
}

enum ResponsiveGeometryResolver {
    static let namespace = "responsive.geometry.v1"
    static func key(_ field: GeometryInspectorField, breakpoint: ResponsiveBreakpoint) -> String {
        "\(namespace).\(breakpoint.id.rawValue.uuidString.lowercased()).\(field.rawValue)"
    }
    static func value(for field: GeometryInspectorField, node: DocumentNode, breakpoint: ResponsiveBreakpoint)
        -> (Double, PropertyOrigin, ResponsiveGeometrySource)? {
        if breakpoint != .desktop,
           let property = node.insertionProperty(key(field, breakpoint: breakpoint)),
           case .number(let value) = property.value, isValid(value, for: field) {
            return (value, property.origin, .override(breakpoint))
        }
        guard let property = node.insertionProperty(field.propertyKey),
              case .number(let value) = property.value, isValid(value, for: field) else { return nil }
        return (value, property.origin, .baseDesktop)
    }
    static func geometry(for node: DocumentNode, breakpoint: ResponsiveBreakpoint) -> InsertionGeometry? {
        guard let x = value(for: .x, node: node, breakpoint: breakpoint)?.0,
              let y = value(for: .y, node: node, breakpoint: breakpoint)?.0,
              let width = value(for: .width, node: node, breakpoint: breakpoint)?.0,
              let height = value(for: .height, node: node, breakpoint: breakpoint)?.0 else { return nil }
        return InsertionGeometry(origin: .init(x: x, y: y), size: .init(width: width, height: height))
    }
    static func frame(for node: DocumentNode, base: WorldRect, breakpoint: ResponsiveBreakpoint) -> WorldRect {
        guard breakpoint != .desktop else { return base }
        func resolved(_ field: GeometryInspectorField, fallback: Double) -> Double {
            value(for: field, node: node, breakpoint: breakpoint)?.0 ?? fallback
        }
        return .init(origin: .init(x: resolved(.x, fallback: base.origin.x), y: resolved(.y, fallback: base.origin.y)),
                     size: .init(width: resolved(.width, fallback: base.size.width),
                                 height: resolved(.height, fallback: base.size.height)))
    }
    private static func isValid(_ value: Double, for field: GeometryInspectorField) -> Bool {
        value.isFinite && abs(value) <= 1_000_000_000 && (!field.requiresPositiveValue || value >= 1)
    }
}

enum ContainerLayoutField: String, CaseIterable, Sendable {
    case padding, gap, axis, alignment, columns
    var title: String {
        switch self { case .padding: "Padding"; case .gap: "Gap"; case .axis: "Direction"; case .alignment: "Alignment"; case .columns: "Columns" }
    }
    var propertyKey: String {
        switch self { case .padding: "layout.padding"; case .gap: "layout.gap"; case .axis: "layout.axis"; case .alignment: "layout.align"; case .columns: "layout.grid.columns" }
    }
    var propertySuffix: String { rawValue }
}

enum ContainerLayoutValue: Equatable, Sendable {
    case number(Double)
    case axis(ContainerLayoutAxis)
    case alignment(ContainerLayoutAlignment)
    var propertyValue: PropertyValue {
        switch self { case .number(let value): .number(value); case .axis(let value): .string(value.rawValue); case .alignment(let value): .string(value.rawValue) }
    }
}

/// SF-0601/SF-0603 — one breakpoint-keyed property cascade is shared by
/// structural layout and its Inspector authoring registry.
enum ResponsiveContainerLayoutResolver {
    static let namespace = "responsive.container.v1"
    static func key(_ field: ContainerLayoutField, breakpoint: ResponsiveBreakpoint) -> String {
        "\(namespace).\(breakpoint.id.rawValue.uuidString.lowercased()).\(field.propertySuffix)"
    }
    static func value(for field: ContainerLayoutField, node: DocumentNode, breakpoint: ResponsiveBreakpoint)
        -> (ContainerLayoutValue, PropertyOrigin, ResponsiveGeometrySource)? {
        if breakpoint != .desktop,
           let property = node.insertionProperty(key(field, breakpoint: breakpoint)),
           let value = parse(property.value, field: field) {
            return (value, property.origin, .override(breakpoint))
        }
        guard let property = node.insertionProperty(field.propertyKey),
              let value = parse(property.value, field: field) else { return nil }
        return (value, property.origin, .baseDesktop)
    }
    private static func parse(_ value: PropertyValue, field: ContainerLayoutField) -> ContainerLayoutValue? {
        switch (field, value) {
        case (.padding, .number(let number))
            where number.isFinite && (0...10_000).contains(number): return .number(number)
        case (.gap, .number(let number))
            where number.isFinite && (0...10_000).contains(number): return .number(number)
        case (.columns, .number(let number))
            where number.isFinite && number.rounded(.towardZero) == number && (1...64).contains(number): return .number(number)
        case (.axis, .string(let value)): return ContainerLayoutAxis(rawValue: value).map(ContainerLayoutValue.axis)
        case (.alignment, .string(let value)): return ContainerLayoutAlignment(rawValue: value).map(ContainerLayoutValue.alignment)
        default: return nil
        }
    }
}

enum ResponsiveVisibilitySource: Equatable, Sendable {
    case baseDesktop
    case override(ResponsiveBreakpoint)
    func label(at breakpoint: ResponsiveBreakpoint) -> String {
        switch self { case .baseDesktop: breakpoint == .desktop ? "Desktop base" : "Inherited from Desktop"; case .override(let value): "Authored for \(value.title)" }
    }
}

enum ResponsiveVisibilityResolver {
    static let namespace = "responsive.visibility.v1"
    static let supportedKinds: Set<NodeKind> = [.frame, .text, .section, .stack, .grid, .image]
    static func supports(_ node: DocumentNode) -> Bool { supportedKinds.contains(node.kind) && node.insertionGeometry != nil }
    static func key(_ breakpoint: ResponsiveBreakpoint) -> String {
        "\(namespace).\(breakpoint.id.rawValue.uuidString.lowercased()).visible"
    }
    static func value(for node: DocumentNode, breakpoint: ResponsiveBreakpoint)
        -> (Bool, PropertyOrigin, ResponsiveVisibilitySource) {
        if breakpoint != .desktop, let property = node.insertionProperty(key(breakpoint)),
           case .boolean(let visible) = property.value { return (visible, property.origin, .override(breakpoint)) }
        let property = node.insertionProperty("hidden")
        return (!node.insertionBooleanProperty("hidden"), property?.origin ?? .defaulted, .baseDesktop)
    }
    static func isVisible(_ node: DocumentNode, breakpoint: ResponsiveBreakpoint) -> Bool {
        supports(node) ? value(for: node, breakpoint: breakpoint).0 : true
    }
}

// SF-0405-001...008 — bounded transactional frame/plain-text insertion foundation.

enum InsertionKind: String, Codable, CaseIterable, Sendable {
    case frame
    case text
    case section
    case stack
    case grid
    case image

    var nodeKind: NodeKind {
        switch self {
        case .frame: .frame
        case .text: .text
        case .section: .section
        case .stack: .stack
        case .grid: .grid
        case .image: .image
        }
    }

    var requirementID: String {
        switch self {
        case .frame, .text: "SF-0405-008"
        case .section: "SF-0405-001"
        case .stack: "SF-0502-001"
        case .grid: "SF-0503-001"
        case .image: "SF-0802-002"
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
        case .image: WorldSize(width: 320, height: 240)
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

struct ImageInsertionCommand: Equatable, Sendable {
    let identity: InsertionOperationIdentity
    let nodeID: NodeID
    let parentID: NodeID
    let index: Int
    let geometry: InsertionGeometry
    let assetID: AssetID
    let provenance: InsertionProvenance
}

enum AuthoringInsertionCommand: Equatable, Sendable {
    case frame(FrameInsertionCommand)
    case text(TextInsertionCommand)
    case container(ContainerInsertionCommand)
    case image(ImageInsertionCommand)

    var kind: InsertionKind {
        switch self {
        case .frame: .frame
        case .text: .text
        case .container(let value): value.kind
        case .image: .image
        }
    }

    var identity: InsertionOperationIdentity {
        switch self {
        case .frame(let value): value.identity
        case .text(let value): value.identity
        case .container(let value): value.identity
        case .image(let value): value.identity
        }
    }

    var nodeID: NodeID {
        switch self {
        case .frame(let value): value.nodeID
        case .text(let value): value.nodeID
        case .container(let value): value.nodeID
        case .image(let value): value.nodeID
        }
    }

    var parentID: NodeID {
        switch self {
        case .frame(let value): value.parentID
        case .text(let value): value.parentID
        case .container(let value): value.parentID
        case .image(let value): value.parentID
        }
    }

    var index: Int {
        switch self {
        case .frame(let value): value.index
        case .text(let value): value.index
        case .container(let value): value.index
        case .image(let value): value.index
        }
    }

    var geometry: InsertionGeometry {
        switch self {
        case .frame(let value): value.geometry
        case .text(let value): value.geometry
        case .container(let value): value.geometry
        case .image(let value): value.geometry
        }
    }

    var provenance: InsertionProvenance {
        switch self {
        case .frame(let value): value.provenance
        case .text(let value): value.provenance
        case .container(let value): value.provenance
        case .image(let value): value.provenance
        }
    }

    var text: String? {
        guard case .text(let value) = self else { return nil }
        return value.text
    }

    var imageAssetID: AssetID? {
        guard case .image(let value) = self else { return nil }
        return value.assetID
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
    case invalidImageAsset
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
        case .invalidImageAsset: "The selected image asset is no longer available in this project."
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
        if let assetID = command.imageAssetID,
           !document.imageAssets.contains(where: { $0.id == assetID }) {
            throw InsertionError.invalidImageAsset
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
        case .image:
            guard let assetID = command.imageAssetID else { break }
            properties += [
                property(command.nodeID, "content.image.v1.assetID", .string(assetID.description), .authored),
                property(command.nodeID, "content.image.v1.fit", .string(ImageFitMode.fit.rawValue), .defaulted),
                property(command.nodeID, "content.image.v1.focal.x", .number(0.5), .defaulted),
                property(command.nodeID, "content.image.v1.focal.y", .number(0.5), .defaulted),
                property(command.nodeID, "content.image.v1.alt", .string(""), .defaulted),
                property(command.nodeID, "content.image.v1.decorative", .boolean(false), .defaulted),
            ]
        case .frame, .text: break
        }
        if let text = command.text {
            properties.append(property(command.nodeID, "content.text", .string(text), .defaulted))
            let typography = CanonicalTypography.defaultValue
            properties += [
                property(command.nodeID, CanonicalTypography.namespace + "family", .string(typography.family), .defaulted),
                property(command.nodeID, CanonicalTypography.namespace + "weight", .string(typography.weight.rawValue), .defaulted),
                property(command.nodeID, CanonicalTypography.namespace + "size", .number(typography.size), .defaulted),
                property(command.nodeID, CanonicalTypography.namespace + "lineHeight", .number(typography.lineHeight), .defaulted),
                property(command.nodeID, CanonicalTypography.namespace + "tracking", .number(typography.tracking), .defaulted),
                property(command.nodeID, CanonicalTypography.namespace + "alignment", .string(typography.alignment.rawValue), .defaulted),
            ]
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
    /// A hidden container suppresses its complete authored subtree at the
    /// active breakpoint without deleting or rewriting descendants. Hidden
    /// children do not consume Stack/Grid placement slots.
    func effectiveVisibleNodeIDs(breakpoint: ResponsiveBreakpoint) -> Set<NodeID> {
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var visible = Set<NodeID>()
        func visit(_ id: NodeID, ancestorVisible: Bool) {
            guard let node = nodesByID[id] else { return }
            let isVisible = ancestorVisible && ResponsiveVisibilityResolver.isVisible(node, breakpoint: breakpoint)
            if isVisible { visible.insert(id) }
            for childID in node.childIDs { visit(childID, ancestorVisible: isVisible) }
        }
        for rootID in rootNodeIDs { visit(rootID, ancestorVisible: true) }
        return visible
    }

    /// Fits authored main-axis lengths into a bounded container without changing
    /// canonical child geometry. Values are preserved while they fit; overflow
    /// is reduced proportionally so resolved/rendered children cannot escape the
    /// container merely because their insertion defaults are larger than a cell.
    private func fittedMainAxisLengths(_ lengths: [Double], available: Double) -> [Double] {
        guard !lengths.isEmpty else { return [] }
        let bounded = lengths.map { max(1, $0) }
        let total = bounded.reduce(0, +)
        guard total > available else { return bounded }
        let minimumTotal = Double(bounded.count)
        guard available > minimumTotal else {
            return Array(repeating: max(1, available / Double(bounded.count)), count: bounded.count)
        }
        let scale = available / total
        return bounded.map { max(1, $0 * scale) }
    }

    func resolvedStructuralGeometry(breakpoint: ResponsiveBreakpoint = .desktop) -> [NodeID: InsertionGeometry] {
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let visibleNodeIDs = effectiveVisibleNodeIDs(breakpoint: breakpoint)
        var result = Dictionary(uniqueKeysWithValues: nodes.compactMap { node in
            node.insertionGeometry.map {
                let base = $0.frame
                let resolved = ResponsiveGeometryResolver.frame(for: node, base: base, breakpoint: breakpoint)
                return (node.id, InsertionGeometry(origin: resolved.origin, size: resolved.size))
            }
        })
        for parent in canonicalDepthFirstNodes() {
            guard let parentGeometry = result[parent.id] else { continue }
            let children = parent.childIDs.filter(visibleNodeIDs.contains).compactMap { nodesByID[$0] }
            switch parent.kind {
            case .section, .stack:
                let padding = ResponsiveContainerLayoutResolver.value(for: .padding, node: parent, breakpoint: breakpoint)
                    .flatMap { if case .number(let value) = $0.0 { value } else { nil } }
                    ?? (parent.kind == .section ? 48 : 24)
                let gap: Double
                if parent.kind == .section {
                    gap = 0
                } else {
                    gap = ResponsiveContainerLayoutResolver.value(for: .gap, node: parent, breakpoint: breakpoint)
                        .flatMap { if case .number(let value) = $0.0 { value } else { nil } } ?? 24
                }
                let axis = parent.kind == .section
                    ? ContainerLayoutAxis.vertical
                    : (ResponsiveContainerLayoutResolver.value(for: .axis, node: parent, breakpoint: breakpoint)
                        .flatMap { if case .axis(let value) = $0.0 { value } else { nil } } ?? .vertical)
                let alignment = parent.kind == .section
                    ? ContainerLayoutAlignment.start
                    : (ResponsiveContainerLayoutResolver.value(for: .alignment, node: parent, breakpoint: breakpoint)
                        .flatMap { if case .alignment(let value) = $0.0 { value } else { nil } } ?? .start)
                let contentWidth = max(1, parentGeometry.size.width - (2 * padding))
                let contentHeight = max(1, parentGeometry.size.height - (2 * padding))
                let availableMain = max(
                    1,
                    (axis == .vertical ? contentHeight : contentWidth) - Double(max(0, children.count - 1)) * gap
                )
                let mainLengths = fittedMainAxisLengths(
                    children.map { child in
                        guard let geometry = result[child.id] else { return 1 }
                        return axis == .vertical ? geometry.size.height : geometry.size.width
                    },
                    available: availableMain
                )
                var cursor = axis == .vertical
                    ? parentGeometry.origin.y + padding
                    : parentGeometry.origin.x + padding
                for (childIndex, child) in children.enumerated() {
                    guard var geometry = result[child.id] else { continue }
                    if axis == .vertical {
                        let width = alignment == .stretch ? contentWidth : min(geometry.size.width, contentWidth)
                        let x: Double = switch alignment {
                        case .start, .stretch: parentGeometry.origin.x + padding
                        case .center: parentGeometry.origin.x + padding + (contentWidth - width) / 2
                        case .end: parentGeometry.origin.x + padding + contentWidth - width
                        }
                        let height = mainLengths[childIndex]
                        geometry = .init(origin: .init(x: x, y: cursor), size: .init(width: width, height: height))
                        cursor += geometry.size.height + gap
                    } else {
                        let height = alignment == .stretch ? contentHeight : min(geometry.size.height, contentHeight)
                        let y: Double = switch alignment {
                        case .start, .stretch: parentGeometry.origin.y + padding
                        case .center: parentGeometry.origin.y + padding + (contentHeight - height) / 2
                        case .end: parentGeometry.origin.y + padding + contentHeight - height
                        }
                        let width = mainLengths[childIndex]
                        geometry = .init(origin: .init(x: cursor, y: y), size: .init(width: width, height: height))
                        cursor += geometry.size.width + gap
                    }
                    result[child.id] = geometry
                }
            case .grid:
                let padding = ResponsiveContainerLayoutResolver.value(for: .padding, node: parent, breakpoint: breakpoint)
                    .flatMap { if case .number(let value) = $0.0 { value } else { nil } } ?? 24
                let gap = ResponsiveContainerLayoutResolver.value(for: .gap, node: parent, breakpoint: breakpoint)
                    .flatMap { if case .number(let value) = $0.0 { value } else { nil } } ?? 24
                let columnValue: Double = ResponsiveContainerLayoutResolver.value(
                    for: .columns, node: parent, breakpoint: breakpoint
                ).flatMap { if case .number(let value) = $0.0 { value } else { nil } } ?? 2
                let columns = max(1, Int(columnValue))
                let usableWidth = max(1, parentGeometry.size.width - (2 * padding) - (Double(columns - 1) * gap))
                let cellWidth = usableWidth / Double(columns)
                let rowCount = children.isEmpty ? 0 : (children.count + columns - 1) / columns
                var authoredRowHeights = Array(repeating: 1.0, count: rowCount)
                for (index, child) in children.enumerated() {
                    authoredRowHeights[index / columns] = max(authoredRowHeights[index / columns], result[child.id]?.size.height ?? 1)
                }
                let availableHeight = max(1, parentGeometry.size.height - (2 * padding) - Double(max(0, rowCount - 1)) * gap)
                let rowHeights = fittedMainAxisLengths(authoredRowHeights, available: availableHeight)
                var rowOffsets = Array(repeating: parentGeometry.origin.y + padding, count: rowCount)
                if rowCount > 1 {
                    for row in 1..<rowCount {
                        rowOffsets[row] = rowOffsets[row - 1] + rowHeights[row - 1] + gap
                    }
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
                        size: .init(width: cellWidth, height: rowHeights[row])
                    )
                    result[child.id] = geometry
                }
            case .frame, .text, .image, .component: break
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
