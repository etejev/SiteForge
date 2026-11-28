import CryptoKit
import Foundation

/// Bound derived graph expansion and renderer preparation with one budget.
/// This is an execution limit, not serialized project state.
enum ResolvedGraphPolicy {
    static let maximumNodes = 20_000
}

/// Canonical v1 structural-layout tokens shared by model validation,
/// deterministic layout resolution, and the Inspector command registry.
enum ContainerLayoutAxis: String, CaseIterable, Sendable { case vertical, horizontal }
enum ContainerLayoutAlignment: String, CaseIterable, Sendable { case start, center, end, stretch }

enum PageFlowRole: String, Codable, CaseIterable, Hashable, Sendable { case header, body, footer }

/// Canonical dependency discovery shared by graph transfer consumers. Values
/// remain stable references; this helper neither loads nor imports resources.
enum CanonicalGraphReferences {
    static func assets(_ node: DocumentNode) -> [AssetID] {
        // OD-038 (ADR-0081): an image a translation shows travels with the node too.
        [CanonicalImageStyle.namespace + "assetID", CanonicalImageFill.assetKey].compactMap {
            node.insertionStringProperty($0).flatMap(AssetID.init(uuidString:))
        } + node.properties.compactMap { property in
            guard CanonicalComponentMedia.overrideID(property.key.rawValue) != nil
                    || SiteTranslationKey(rawValue: property.key.rawValue)?.field == .imageAssetID,
                  case .string(let raw) = property.value else { return nil }
            return AssetID(uuidString: raw)
        }
    }
    static func tokens(_ node: DocumentNode) -> [ColorTokenID] {
        LocalColorTarget.allCases.compactMap { LocalColorTokenBinding.id(for: node, target: $0) }
    }
}

/// Header/Footer contents remain ordinary editable nodes. These references
/// identify their roles; they do not duplicate title text, links or layout.
enum CanonicalPageChrome {
    /// Existing native Preview menu budget, shared with automatic row layout.
    /// This is derived editor/output policy, never an authored dimension.
    static let menuControlWidth = 90.0
    static let namespace = "page.chrome.v1."
    static let titleKey = namespace + "titleID"
    static let contentKey = namespace + "contentID"
    static let navigationKey = namespace + "navigationID"
    static let arrangementKey = namespace + "arrangement"
    static let referenceKeys: Set<String> = [titleKey, contentKey, navigationKey]
    static func reference(_ key: String, on owner: DocumentNode) -> NodeID? {
        owner.insertionStringProperty(key).flatMap(NodeID.init(uuidString:))
    }
    static func isCustom(_ owner: DocumentNode) -> Bool { owner.insertionStringProperty(arrangementKey) == "custom" }
    struct TitleResolution: Equatable, Sendable {
        let text: String
        let provenance: String
    }
    static func resolvedTitle(_ title: DocumentNode, in document: CanonicalDocument) -> TitleResolution {
        guard let property = title.insertionProperty("content.text"), case .string(let stored) = property.value else {
            return .init(text: "", provenance: "Missing title content. Restore it with Undo.")
        }
        if property.origin == .authored { return .init(text: stored, provenance: "Authored title") }
        if let name = document.websiteMetadata?.siteName { return .init(text: name, provenance: "Defaulted from Site Name") }
        if let home = document.websitePages.first(where: { $0.role == .home }) {
            return .init(text: home.name, provenance: "Defaulted from Home page")
        }
        return .init(text: stored, provenance: stored.isEmpty
            ? "No title source. Enter a title or set Site Name in Site Settings."
            : "Stored default title")
    }
    static func titleText(_ title: DocumentNode, in document: CanonicalDocument) -> String {
        resolvedTitle(title, in: document).text
    }
    static func ownsFrame(of node: DocumentNode, in page: DocumentPage) -> Bool {
        guard let owner = owner(of: node, in: page) else { return false }
        return reference(contentKey, on: owner) == node.id ||
            (reference(navigationKey, on: owner) == node.id && !isCustom(owner))
    }
    static func owner(of node: DocumentNode, in page: DocumentPage) -> DocumentNode? {
        page.nodes.first { owner in
            [PageFlowRole.header, .footer].contains(CanonicalPageFlow.role(owner)) &&
                referenceKeys.contains { reference($0, on: owner) == node.id }
        }
    }
    static func navigationOwner(of link: DocumentNode, in page: DocumentPage) -> DocumentNode? {
        guard case .node(let parentID) = link.parent, let parent = page.nodes.first(where: { $0.id == parentID }) else { return nil }
        if [.header, .footer].contains(CanonicalPageFlow.role(parent)) { return parent }
        return page.nodes.first { reference(navigationKey, on: $0) == parent.id && [.header, .footer].contains(CanonicalPageFlow.role($0)) }
    }
    static func links(owner: DocumentNode, page: DocumentPage) -> [DocumentNode] {
        let container: DocumentNode
        if let id = reference(navigationKey, on: owner) {
            guard let node = page.nodes.first(where: { $0.id == id }) else { return [] }
            container = node
        } else { container = owner }
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        return container.childIDs.compactMap { byID[$0] }.filter(CanonicalPageFlow.isNavigationLink)
    }
    static func navigationOwnersBySurface(in page: DocumentPage) -> [NodeID: DocumentNode] {
        var owners: [NodeID: DocumentNode] = [:]
        for node in page.nodes where [.header, .footer].contains(CanonicalPageFlow.role(node)) {
            guard let surface = reference(navigationKey, on: node), owners[surface] == nil else { continue }
            owners[surface] = node
        }
        return owners
    }

    static func navigationSettings(for surface: DocumentNode, page: DocumentPage,
                                   ownersBySurface: [NodeID: DocumentNode]? = nil) -> DocumentNode? {
        if [.header, .footer].contains(CanonicalPageFlow.role(surface)) {
            return reference(navigationKey, on: surface) == nil ? surface : nil
        }
        if let ownersBySurface { return ownersBySurface[surface.id] }
        return page.nodes.first { reference(navigationKey, on: $0) == surface.id && [.header, .footer].contains(CanonicalPageFlow.role($0)) }
    }
    static func hasUsableNavigation(owner: DocumentNode, page: DocumentPage,
                                    availablePageIDs: Set<PageID>, breakpoint: ResponsiveBreakpoint) -> Bool {
        let visible = page.effectiveVisibleNodeIDs(breakpoint: breakpoint)
        return links(owner: owner, page: page).contains { node in
            guard visible.contains(node.id), let target = try? CanonicalLinkTarget.resolve(node),
                  case .page(let id) = target else { return false }
            return availablePageIDs.contains(id)
        }
    }
    /// The collapsed menu is derived chrome for this authored navigation.
    /// Inherit only a genuinely shared link typography/color; mixed links
    /// never borrow the first link's styling as an implicit winning value.
    static func uniformNavigationTextSource(surface: DocumentNode, page: DocumentPage,
                                            tokens: [LocalColorToken]) -> DocumentNode? {
        let members = links(owner: surface, page: page)
        guard navigationSettings(for: surface, page: page) != nil,
              let first = members.first,
              let typography = TypographyCommandRegistry.resolvedTypography(for: first),
              let foreground = LocalColorTokenResolver.textForeground(for: first, tokens: tokens),
              members.allSatisfy({ TypographyCommandRegistry.resolvedTypography(for: $0) == typography
                  && LocalColorTokenResolver.textForeground(for: $0, tokens: tokens) == foreground }) else { return nil }
        return first
    }
    static func opaqueNavigationSurface(surface: DocumentNode, page: DocumentPage,
                                        tokens: [LocalColorToken]) -> CanonicalSolidColor? {
        guard let owner = navigationSettings(for: surface, page: page) else { return nil }
        let layers = LocalColorTokenResolver.resolvedLayers(for: owner, tokens: tokens).filter(\.isEnabled)
        guard layers.count == 1, let color = layers.first?.solidColor, color.alpha == 1 else { return nil }
        return color
    }
    static func navigationForeground(surface: DocumentNode, page: DocumentPage,
                                     tokens: [LocalColorToken]) -> CanonicalSolidColor? {
        if let source = uniformNavigationTextSource(surface: surface, page: page, tokens: tokens) {
            return LocalColorTokenResolver.textForeground(for: source, tokens: tokens)
        }
        guard let color = opaqueNavigationSurface(surface: surface, page: page, tokens: tokens) else { return nil }
        let luminance = 0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
        let channel = luminance > 0.5 ? 0.0 : 1.0
        return .init(red: channel, green: channel, blue: channel, alpha: 1)
    }
    /// Editable nested navigation defaults to the trailing side of its
    /// Header/Footer row; legacy navigation directly on the owner starts at
    /// its padding. Native layout, Preview and CSS must share this default.
    static func navigationAlignment(surface: DocumentNode, settings: DocumentNode) -> String {
        settings.insertionStringProperty(CanonicalPageFlow.alignmentKey)
            ?? (settings.id == surface.id ? "start" : "end")
    }
    static func navigationGap(surface: DocumentNode, settings: DocumentNode,
                              breakpoint: ResponsiveBreakpoint, width: Double?) -> Double {
        guard settings.id != surface.id,
              let resolved = ResponsiveContainerLayoutResolver.value(for: .gap, node: surface,
                  breakpoint: breakpoint, viewportWidth: width),
              case .number(let value) = resolved.0 else { return CanonicalPageFlow.navigationGap }
        return value
    }
    static func resolvedLabels(in page: DocumentPage, document: CanonicalDocument) -> DocumentPage {
        var result = page
        let names = Dictionary(uniqueKeysWithValues: document.websitePages.map { ($0.id, $0.name) })
        let titleIDs = Set(page.nodes.compactMap { reference(titleKey, on: $0) })
        for index in result.nodes.indices {
            let node = result.nodes[index]
            let key: String
            let text: String
            if CanonicalPageFlow.isNavigationLink(node), let target = try? CanonicalLinkTarget.resolve(node),
               case .page(let id) = target, let name = names[id] { key = CanonicalLinkTarget.labelKey; text = name }
            else if titleIDs.contains(node.id) { key = "content.text"; text = titleText(node, in: document) }
            else { continue }
            if let property = result.nodes[index].properties.firstIndex(where: { $0.key.rawValue == key && $0.origin != .authored }) {
                result.nodes[index].properties[property].value = .string(text)
            }
        }
        return result
    }
    struct Contents {
        let title: DocumentNode
        let navigation: DocumentNode
        let content: DocumentNode
        let links: [DocumentNode]
        var nodes: [DocumentNode] { [content, title, navigation] + links }
        var references: [(String, PropertyValue)] {
            [(titleKey, .string(title.id.description)), (contentKey, .string(content.id.description)),
             (navigationKey, .string(navigation.id.description)), (arrangementKey, .string("automatic"))]
        }
    }
    static func defaults(ownerID: NodeID, document: CanonicalDocument) -> Contents {
        func id(_ label: String) -> NodeID { .init(DocumentPage.deterministicUUID(namespace: ownerID.rawValue, label: "page-chrome." + label)) }
        func property(_ nodeID: NodeID, _ key: String, _ value: PropertyValue) -> NodeProperty {
            .init(id: .init(DocumentPage.deterministicUUID(namespace: nodeID.rawValue, label: key)),
                  key: .init(rawValue: key), value: value, origin: .defaulted)
        }
        func geometry(_ nodeID: NodeID, width: Double, height: Double) -> [NodeProperty] {
            [("layout.x", 0.0), ("layout.y", 0.0), ("layout.width", width), ("layout.height", height)]
                .map { property(nodeID, $0.0, .number($0.1)) }
        }
        func stack(_ nodeID: NodeID, name: String, parent: NodeID, children: [NodeID], gap: Double) -> DocumentNode {
            .init(id: nodeID, kind: .stack, name: name, parent: .node(parent), childIDs: children,
                properties: geometry(nodeID, width: 600, height: 32) + [
                    property(nodeID, "layout.container.kind", .string("stack")),
                    property(nodeID, "layout.axis", .string("horizontal")),
                    property(nodeID, "layout.padding", .number(0)), property(nodeID, "layout.gap", .number(gap)),
                    property(nodeID, "layout.align", .string("center")),
                    property(nodeID, "style.fill.layers.v1.order", .string("")),
                    property(nodeID, "style.border", .string("none"))])
        }
        let contentID = id("content"), navigationID = id("navigation"), titleID = id("title")
        let pages = document.websitePages.filter { $0.role != .notFound }
        let links = pages.prefix(CanonicalPageFlow.maximumLinks).map { destination -> DocumentNode in
            let nodeID = id("page." + destination.id.description)
            return .init(id: nodeID, kind: .link, name: destination.name, parent: .node(navigationID),
                properties: geometry(nodeID, width: 120, height: 32) + [
                    property(nodeID, CanonicalPageFlow.memberKey, .boolean(true)),
                    property(nodeID, CanonicalLinkTarget.namespace + "kind", .string("page")),
                    property(nodeID, CanonicalLinkTarget.namespace + "pageID", .string(destination.id.description)),
                    property(nodeID, CanonicalLinkTarget.labelKey, .string(destination.name))])
        }
        let title = DocumentNode(id: titleID, kind: .text, name: "Site title", parent: .node(contentID),
            properties: geometry(titleID, width: 200, height: 24) + [
                property(titleID, "content.text", .string(document.websitePages.first(where: { $0.role == .home })?.name ?? ""))])
        return .init(title: title,
            navigation: stack(navigationID, name: "Navigation", parent: contentID, children: links.map(\.id), gap: 16),
            content: stack(contentID, name: "Content", parent: ownerID, children: [titleID, navigationID], gap: 24), links: links)
    }
    static func validate(_ owner: DocumentNode, in page: DocumentPage) throws {
        let owned = owner.properties.filter { $0.key.rawValue.hasPrefix(namespace) }
        guard !owned.isEmpty else { return }
        guard [.header, .footer].contains(CanonicalPageFlow.role(owner)),
              Set(owned.map { $0.key.rawValue }).isSubset(of: referenceKeys.union([arrangementKey])),
              owned.allSatisfy({ $0.origin == .authored || $0.origin == .defaulted }),
              let titleID = reference(titleKey, on: owner), let contentID = reference(contentKey, on: owner),
              let navigationID = reference(navigationKey, on: owner), Set([titleID, contentID, navigationID]).count == 3,
              ["automatic", "custom"].contains(owner.insertionStringProperty(arrangementKey) ?? "automatic") else {
            throw ModelValidationError.invalidSemanticElementState
        }
        let expected: [(NodeID, NodeKind, NodeID)] = [(contentID, .stack, owner.id), (titleID, .text, contentID), (navigationID, .stack, contentID)]
        for (id, kind, parent) in expected {
            // Missing references remain recoverable intent. Existing targets
            // must never borrow an unrelated node or cross a hierarchy.
            if let node = page.nodes.first(where: { $0.id == id }) {
                guard node.kind == kind else { throw ModelValidationError.invalidSemanticElementState }
                if CanonicalPageFlow.role(owner) == .footer, id != contentID {
                    var cursor = node, visited = Set<NodeID>()
                    while cursor.parent != .node(contentID) {
                        guard visited.insert(cursor.id).inserted, visited.count <= 256,
                              case .node(let parentID) = cursor.parent,
                              let next = page.nodes.first(where: { $0.id == parentID }), next.kind.acceptsAuthoredChildren
                        else { throw ModelValidationError.invalidSemanticElementState }
                        cursor = next
                    }
                } else if node.parent != .node(parent) { throw ModelValidationError.invalidSemanticElementState }
            }
        }
    }
}

struct PageNavigationLink: Codable, Hashable, Sendable, Identifiable {
    let id: NodeID
    let pageID: PageID
    let label: String
    let isAvailable: Bool
    var context: CanonicalLinkContext? = nil
}

struct PageNavigationSnapshot: Codable, Hashable, Sendable {
    let ownerID: NodeID
    let links: [PageNavigationLink]
    let hamburgerEnabled: Bool
    let usesHamburger: Bool
    let alignment: String
    let padding: Double
    var currentPageID: PageID? = nil
    var rowHeight: Double? = nil
    var itemFrames: [PageNavigationItemFrame] = []
}

struct PageNavigationItemFrame: Codable, Hashable, Sendable {
    let id: NodeID
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

/// Opt-in page structure. Canonical ownership order and authored heights are
/// retained; x/y/width are resolved from the containing area, never a viewport
/// coordinate store. Historical unmarked Sections retain absolute behavior.
enum CanonicalPageFlow {
    static let namespace = "page.flow.v1."
    static let roleKey = namespace + "role"
    static let navigationNamespace = "page.navigation.v1."
    static let memberKey = navigationNamespace + "member"
    static let hamburgerKey = navigationNamespace + "hamburger"
    static let alignmentKey = navigationNamespace + "alignment"
    static let maximumLinks = 32
    static let navigationGap = 16.0
    static func navigationLayout(availableWidth: Double, count: Int, alignment: String,
                                 requestedGap: Double? = nil) -> (width: Double, gap: Double, offset: Double) {
        guard count > 0 else { return (0, 0, 0) }
        let available = max(1, availableWidth)
        let preferred = requestedGap.flatMap { $0.isFinite && (0...10_000).contains($0) ? $0 : nil } ?? navigationGap
        let gap = count > 1 ? min(preferred, max(0, (available - Double(count)) / Double(count - 1))) : 0
        let width = min(alignment == "stretch" ? Double.greatestFiniteMagnitude : 160,
                        (available - gap * Double(count - 1)) / Double(count))
        let total = width * Double(count) + gap * Double(count - 1)
        return (width, gap, alignment == "end" ? max(0, available - total) : alignment == "center" ? max(0, available - total) / 2 : 0)
    }
    static func role(_ node: DocumentNode) -> PageFlowRole? {
        node.insertionStringProperty(roleKey).flatMap(PageFlowRole.init(rawValue:))
    }
    static func isNavigationLink(_ node: DocumentNode) -> Bool { node.insertionProperty(memberKey)?.value == .boolean(true) }
    static func isManaged(_ node: DocumentNode) -> Bool { role(node) != nil || isNavigationLink(node) }
    static func padding(_ node: DocumentNode, breakpoint: ResponsiveBreakpoint, width: Double?) -> Double {
        DesignBoxStyleCommandRegistry.resolvedStyle(for: node)?.padding
            ?? ResponsiveContainerLayoutResolver.value(for: .padding, node: node, breakpoint: breakpoint, viewportWidth: width)
                .flatMap { if case .number(let value) = $0.0 { value } else { nil } } ?? 48
    }
    static func ordered(_ children: [DocumentNode]) -> [DocumentNode] {
        children.filter { role($0) == .header } + children.filter { role($0) == .body } + children.filter { role($0) == .footer }
    }
    static func pageWidth(_ breakpoint: ResponsiveBreakpoint, _ width: Double?) -> Double {
        max(1, width ?? (breakpoint == .desktop ? 1440 : breakpoint == .tablet ? 768 : 390))
    }
    static func insertionIndex(role: PageFlowRole, parent: DocumentNode, page: DocumentPage,
                               pointerY: Double?, breakpoint: ResponsiveBreakpoint, width: Double?, excluding: NodeID? = nil) -> Int {
        let nodes = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let children = parent.childIDs.compactMap { nodes[$0] }
        if role == .header { return 0 }
        if role == .footer { return parent.childIDs.count }
        let visible = page.effectiveVisibleNodeIDs(breakpoint: breakpoint)
        let body = children.filter { self.role($0) == .body && $0.id != excluding && visible.contains($0.id) }
        if let pointerY {
            let frames = page.resolvedStructuralGeometry(breakpoint: breakpoint, viewportWidth: width)
            if let next = body.first(where: { frames[$0.id].map { pointerY < $0.frame.minY + $0.size.height / 2 } ?? false }) {
                return parent.childIDs.firstIndex(of: next.id) ?? parent.childIDs.count
            }
        }
        return children.first(where: { self.role($0) == .footer }).flatMap { parent.childIDs.firstIndex(of: $0.id) }
            ?? parent.childIDs.count
    }
    static func boundaryFrame(parent: DocumentNode, page: DocumentPage, index: Int,
                              breakpoint: ResponsiveBreakpoint, width: Double, excluding: NodeID? = nil) -> WorldRect {
        let snapshot = ConnectedPageLayoutSnapshot(page: page, breakpoint: breakpoint, width: width)
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let policy = snapshot.policies[parent.id] ?? ResolvedContainerLayoutPolicy.resolve(parent, children: [], breakpoint: breakpoint, viewportWidth: width)
        let eligible = parent.childIDs.enumerated().compactMap { offset, id -> (Int, InsertionGeometry)? in
            guard id != excluding, snapshot.visibleIDs.contains(id), let node = byID[id],
                  !isNavigationLink(node), !policy.naturalFlow || role(node) != nil,
                  let frame = snapshot.frames[id] else { return nil }
            return (offset, frame)
        }
        let parentFrame = snapshot.frames[parent.id]
        let origin = parentFrame?.origin ?? .init(x: 0, y: 0)
        let next = eligible.first { $0.0 >= index }?.1
        let y = next?.origin.y ?? eligible.map { $0.1.frame.maxY }.max() ?? (origin.y + policy.padding)
        let availableWidth = page.rootNodeIDs.contains(parent.id) ? min(parentFrame?.size.width ?? width, width) : parentFrame?.size.width ?? width
        return .init(origin: .init(x: parent.kind == .grid ? (next?.origin.x ?? origin.x + policy.padding) : origin.x + policy.padding, y: y),
                     size: .init(width: parent.kind == .grid ? (next?.size.width ?? max(1, availableWidth - 2 * policy.padding)) : max(1, availableWidth - 2 * policy.padding), height: 1))
    }
    static func contentHeight(_ page: DocumentPage?, breakpoint: ResponsiveBreakpoint, width: Double) -> Double {
        guard let page else { return 900 }
        let frames = page.resolvedStructuralGeometry(breakpoint: breakpoint, viewportWidth: width)
        let visible = page.effectiveVisibleNodeIDs(breakpoint: breakpoint)
        return contentHeight(page, frames: frames, visibleIDs: visible)
    }
    static func contentHeight(_ page: DocumentPage, frames: [NodeID: InsertionGeometry], visibleIDs: Set<NodeID>) -> Double {
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        return page.nodes.filter { role($0) != nil && visibleIDs.contains($0.id) }.compactMap { node in
            guard let frame = frames[node.id] else { return nil }
            let bottomPadding: Double
            if case .node(let parent) = node.parent, page.rootNodeIDs.contains(parent), let owner = byID[parent] {
                bottomPadding = DesignBoxStyleCommandRegistry.resolvedStyle(for: owner)?.padding ?? 0
            } else { bottomPadding = 0 }
            return frame.frame.maxY + bottomPadding
        }.reduce(900, max)
    }
    static func unsupportedStaticContainers(_ page: DocumentPage, availablePageIDs: Set<PageID>? = nil) -> [NodeID] {
        guard page.nodes.contains(where: { role($0) != nil }) else { return [] }
        // Nested containers now have semantic ownership. Independent roots and
        // non-free positioning still need a different browser containing block.
        let failures = outputFailures(page, availablePageIDs: availablePageIDs)
        return page.nodes.filter { failures[$0.id] != nil }.map(\.id)
    }
    static func outputFailures(_ page: DocumentPage, availablePageIDs: Set<PageID>? = nil) -> [NodeID: ConnectedFluidOutputPolicy.Failure] {
        guard page.nodes.contains(where: { role($0) != nil }) else { return [:] }
        let fluid = ConnectedFluidOutputPolicy.failures(page)
        return Dictionary(uniqueKeysWithValues: page.nodes.compactMap { node in
            outputFailure(for: node, page: page, fluidFailures: fluid, availablePageIDs: availablePageIDs).map { (node.id, $0) }
        })
    }
    static func outputFailure(for node: DocumentNode, page: DocumentPage,
        fluidFailures: [NodeID: ConnectedFluidOutputPolicy.Failure]? = nil,
        availablePageIDs: Set<PageID>? = nil) -> (code: String, explanation: String, repair: String)? {
        // Caller has already established a connected page; do not rescan the
        // complete graph for every node during large output preflight.
        if page.rootNodeIDs.count != 1, role(node) != nil {
            return ("page-flow-containing-block", "Connected output needs one page root, not independent containing blocks.", "Keep one root or use native Preview until multiple-root output is supported.")
        }
            if !isManaged(node), let position = CanonicalPositioning.resolve(node),
               [.relative, .fixed, .sticky].contains(position.mode) || position.top != nil || position.left != nil || position.right != nil || position.bottom != nil {
                return ("page-flow-positioning", "This positioned node needs a browser containing-block policy beyond connected free geometry.", "Reset positioning explicitly or keep native Preview. Original properties remain unchanged.")
            }
            if node.insertionProperty(hamburgerKey)?.value == .boolean(true),
               DesignBoxStyleCommandRegistry.resolvedStyle(for: node)?.clipsContent == true {
                return ("page-flow-navigation-clipped", "Authored clipping would cut off the exported expanded navigation panel.", "Disable clipping explicitly or keep native Preview's native menu until a clipped-container browser menu is supported.")
            }
        if let room = CanonicalPageChrome.mobileOutputRoomFailure(owner: node, page: page,
            availablePageIDs: availablePageIDs) { return room }
        return (fluidFailures ?? ConnectedFluidOutputPolicy.failures(page))[node.id]
    }
    static func navigation(owner: DocumentNode, page: DocumentPage, document: CanonicalDocument,
                           breakpoint: ResponsiveBreakpoint, width: Double? = nil) -> PageNavigationSnapshot? {
        let owner = CanonicalPageChrome.reference(CanonicalPageChrome.navigationKey, on: owner)
            .flatMap { id in page.nodes.first { $0.id == id } } ?? owner
        guard let settings = CanonicalPageChrome.navigationSettings(for: owner, page: page) else { return nil }
        let nodes = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let visible = page.effectiveVisibleNodeIDs(breakpoint: breakpoint)
        let links = CanonicalPageChrome.links(owner: owner, page: page).compactMap { source -> PageNavigationLink? in
            let id = source.id
            guard visible.contains(id), let node = nodes[id], isNavigationLink(node), let value = try? CanonicalLinkTarget.resolve(node),
                  case .page(let target) = value else { return nil }
            let destination = document.websitePages.first { $0.id == target }
            let labelProperty = node.insertionProperty(CanonicalLinkTarget.labelKey)
            let label = labelProperty?.origin == .authored ? node.controlLabel : (destination?.name ?? node.controlLabel)
            return .init(id: id, pageID: target, label: label, isAvailable: destination != nil, context: node.controlContext)
        }
        guard !links.isEmpty else { return nil }
        let enabled = settings.insertionProperty(hamburgerKey)?.value == .boolean(true)
        let isNested = settings.id != owner.id
        let inset = isNested ? 0 : padding(owner, breakpoint: breakpoint, width: width)
        let frames = isNested ? page.resolvedStructuralGeometry(breakpoint: breakpoint, viewportWidth: width,
            availablePageIDs: Set(document.websitePages.map(\.id))) : [:]
        let bounds = frames[owner.id]?.frame
        let height = bounds?.size.height ?? ResponsiveGeometryResolver.value(for: .height, node: owner, breakpoint: breakpoint, viewportWidth: width)?.0 ?? 120
        let hasUsableLink = links.contains(where: \.isAvailable)
        var snapshot = PageNavigationSnapshot(ownerID: settings.id, links: links, hamburgerEnabled: enabled,
            usesHamburger: enabled && hasUsableLink && (width.map { $0 < 600 } ?? (breakpoint == .mobile)),
            alignment: CanonicalPageChrome.navigationAlignment(surface: owner, settings: settings),
            padding: inset, currentPageID: page.id, rowHeight: min(32, max(1, height - 2 * inset)))
        if let bounds {
            snapshot.rowHeight = bounds.size.height
            snapshot.itemFrames = links.compactMap { link in
                guard let frame = frames[link.id]?.frame else { return nil }
                return .init(id: link.id, x: frame.origin.x - bounds.origin.x, y: frame.origin.y - bounds.origin.y,
                             width: frame.size.width, height: frame.size.height)
            }
        }
        return snapshot
    }
    static func validate(_ page: DocumentPage) throws {
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        var headers = Set<NodeID>(), footers = Set<NodeID>()
        for node in page.nodes {
            let metadata = node.properties.filter { $0.key.rawValue.hasPrefix(namespace) || $0.key.rawValue.hasPrefix(navigationNamespace) }
            guard !metadata.isEmpty else { continue }
            guard page.role != .componentDefinition,
                  metadata.allSatisfy({ $0.origin == .authored || $0.origin == .defaulted }),
                  Set(metadata.map(\.key.rawValue)).isSubset(of: [roleKey, memberKey, hamburgerKey, alignmentKey]) else {
                throw ModelValidationError.invalidSemanticElementState
            }
            if let role = role(node) {
                guard node.kind == .section, case .node(let parent) = node.parent, byID[parent] != nil else {
                    throw ModelValidationError.invalidSemanticElementState
                }
                if role == .header || role == .footer {
                    guard parent == page.rootNodeIDs.first,
                          CanonicalSemanticElement.resolved(for: node)?.0 == (role == .header ? .header : .footer) else {
                        throw ModelValidationError.invalidSemanticElementState
                    }
                    let managed = byID[parent]?.childIDs.compactMap { byID[$0] }.filter { self.role($0) != nil } ?? []
                    guard (role == .header ? managed.first?.id : managed.last?.id) == node.id else {
                        throw ModelValidationError.invalidSemanticElementState
                    }
                    if role == .header { guard headers.insert(parent).inserted else { throw ModelValidationError.invalidSemanticElementState } }
                    else { guard footers.insert(parent).inserted else { throw ModelValidationError.invalidSemanticElementState } }
                } else {
                    let semantic = CanonicalSemanticElement.resolved(for: node)?.0
                    guard semantic != .header, semantic != .footer else { throw ModelValidationError.invalidSemanticElementState }
                }
                if let hamburger = node.insertionProperty(hamburgerKey) {
                    guard role != .body, case .boolean = hamburger.value else { throw ModelValidationError.invalidSemanticElementState }
                }
                if let alignment = node.insertionStringProperty(alignmentKey) {
                    guard role != .body, ContainerLayoutAlignment(rawValue: alignment) != nil else { throw ModelValidationError.invalidSemanticElementState }
                } else if node.insertionProperty(alignmentKey) != nil { throw ModelValidationError.invalidSemanticElementState }
                guard node.insertionProperty(memberKey) == nil,
                      CanonicalPageChrome.links(owner: node, page: page).count <= maximumLinks else {
                    throw ModelValidationError.invalidSemanticElementState
                }
                if !CanonicalPageChrome.links(owner: node, page: page).isEmpty {
                    for breakpoint in ResponsiveBreakpoint.allCases {
                        let height = ResponsiveGeometryResolver.value(for: .height, node: node, breakpoint: breakpoint)?.0 ?? 0
                        guard height >= 2 * padding(node, breakpoint: breakpoint, width: pageWidth(breakpoint, nil)) + 24 else {
                            throw ModelValidationError.invalidSemanticElementState
                        }
                    }
                }
            } else {
                guard metadata.count == 1, isNavigationLink(node), node.kind == .link,
                      let owner = CanonicalPageChrome.navigationOwner(of: node, in: page),
                      let ownerRole = role(owner), ownerRole == .header || ownerRole == .footer,
                      let target = try? CanonicalLinkTarget.resolve(node), case .page = target else {
                    throw ModelValidationError.invalidSemanticElementState
                }
            }
        }
        let flowByParent = Dictionary(grouping: page.nodes.filter { role($0) != nil }, by: { node in
            if case .node(let parent) = node.parent { return parent }; return node.id
        })
        for children in flowByParent.values {
            for breakpoint in ResponsiveBreakpoint.allCases {
                let total = children.reduce(0.0) { sum, node in
                    sum + (ResponsiveGeometryResolver.value(for: .height, node: node, breakpoint: breakpoint)?.0 ?? 0)
                }
                guard total.isFinite, total <= LayoutPolicy.maximumDimension else { throw ModelValidationError.invalidSemanticElementState }
            }
        }
    }
}

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

enum ColorTokenIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "color-token"
}

enum FormOptionIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "form-option"
}

enum ReusableStyleIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "reusable-style"
}

typealias DocumentID = StableIdentifier<DocumentIdentifierDomain>
typealias PageID = StableIdentifier<PageIdentifierDomain>
typealias NodeID = StableIdentifier<NodeIdentifierDomain>
typealias PropertyID = StableIdentifier<PropertyIdentifierDomain>
typealias TemplateID = StableIdentifier<TemplateIdentifierDomain>
typealias GuideID = StableIdentifier<GuideIdentifierDomain>
typealias ResourceID = StableIdentifier<ResourceIdentifierDomain>
typealias AssetID = StableIdentifier<AssetIdentifierDomain>
typealias ColorTokenID = StableIdentifier<ColorTokenIdentifierDomain>
typealias FormOptionID = StableIdentifier<FormOptionIdentifierDomain>
typealias ReusableStyleID = StableIdentifier<ReusableStyleIdentifierDomain>

/// Shared canonical RGBA value: document serialization and headless project
/// validation must not depend on the editor's transform/Inspector module.
struct CanonicalSolidColor: Codable, Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static let legacySurface = CanonicalSolidColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1)

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    var isValid: Bool { [red, green, blue, alpha].allSatisfy { $0.isFinite && (0...1).contains($0) } }
    var hexadecimalRGBA: String {
        func channel(_ value: Double) -> String { String(format: "%02X", Int((value * 255).rounded())) }
        return "#\(channel(red))\(channel(green))\(channel(blue))\(channel(alpha))"
    }

    /// CSS gradient interpolation uses premultiplied sRGB components; the
    /// stored result remains straight RGBA so ordinary compositing applies once.
    static func premultipliedInterpolation(_ a: Self, _ b: Self, fraction: Double) -> Self? {
        guard a.isValid, b.isValid, fraction.isFinite, (0...1).contains(fraction) else { return nil }
        let alpha = a.alpha * (1 - fraction) + b.alpha * fraction
        guard alpha > 0 else { return .init(red: 0, green: 0, blue: 0, alpha: 0) }
        func channel(_ x: Double, _ y: Double) -> Double {
            (x * a.alpha * (1 - fraction) + y * b.alpha * fraction) / alpha
        }
        return .init(red: channel(a.red, b.red), green: channel(a.green, b.green), blue: channel(a.blue, b.blue), alpha: alpha)
    }

    static func parse(hexadecimal: String) -> CanonicalSolidColor? {
        let source = hexadecimal.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = source.hasPrefix("#") ? String(source.dropFirst()) : source
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard digits.count == 6 || digits.count == 8,
              digits.unicodeScalars.allSatisfy({ hex.contains($0) }) else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: digits).scanHexInt64(&value) else { return nil }
        let divisor = 255.0
        if digits.count == 6 {
            return CanonicalSolidColor(red: Double((value >> 16) & 0xff) / divisor, green: Double((value >> 8) & 0xff) / divisor, blue: Double(value & 0xff) / divisor, alpha: 1)
        }
        return CanonicalSolidColor(red: Double((value >> 24) & 0xff) / divisor, green: Double((value >> 16) & 0xff) / divisor, blue: Double((value >> 8) & 0xff) / divisor, alpha: Double(value & 0xff) / divisor)
    }
}

/// A single project-local collection. Its array order and stable IDs are
/// canonical; presentation drafts and color-panel state are not.
/// SF-0508/SF-1101/SF-1103: only authored configuration is canonical.
/// Pointer position, velocity and deformation never enter these properties.
struct CanonicalFlowGradient: Equatable, Sendable {
    static let namespace = "style.flow.v1."
    static let documentSchema = 21
    static let defaults = Self(enabled: true, radius: 240, strength: 0.65, response: 10, returnSeconds: 0.8)
    var enabled: Bool
    var radius: Double
    var strength: Double
    var response: Double
    var returnSeconds: Double
    var isValid: Bool {
        radius.isFinite && (24...1_200).contains(radius)
            && strength.isFinite && (0...1).contains(strength)
            && response.isFinite && (0.5...30).contains(response)
            && returnSeconds.isFinite && (0.1...5).contains(returnSeconds)
    }
    var properties: [String: PropertyValue] {
        [Self.namespace + "enabled": .boolean(enabled), Self.namespace + "radius": .number(radius),
         Self.namespace + "strength": .number(strength), Self.namespace + "response": .number(response),
         Self.namespace + "returnSeconds": .number(returnSeconds)]
    }
    static func resolve(_ node: DocumentNode) throws -> Self? {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix("style.flow.") }
        guard !owned.isEmpty else { return nil }
        let keys = Set(defaults.properties.keys)
        guard [.frame, .section].contains(node.kind), Set(owned.map(\.key.rawValue)) == keys,
              owned.count == keys.count,
              case .boolean(let enabled)? = node.insertionProperty(namespace + "enabled")?.value,
              let radius = node.insertionNumberProperty(namespace + "radius"),
              let strength = node.insertionNumberProperty(namespace + "strength"),
              let response = node.insertionNumberProperty(namespace + "response"),
              let duration = node.insertionNumberProperty(namespace + "returnSeconds") else {
            throw ModelValidationError.invalidInteractionStyleState
        }
        let result = Self(enabled: enabled, radius: radius, strength: strength, response: response, returnSeconds: duration)
        guard result.isValid else { throw ModelValidationError.invalidInteractionStyleState }
        return result
    }
    static let unavailableReason = "Flow needs one enabled linear-gradient fill on a Frame, Section or page background, without an image fill. Keep or restore that fill, or disable Flow."
}

/// Optional glass uses the ordinary authored fill when supported, and an
/// explicit opaque surface when backdrop blur/transparency is unavailable.
struct CanonicalGlassSurface: Equatable, Sendable {
    static let namespace = "style.glass.v1."
    var blur: Double
    var fallback: CanonicalSolidColor
    var darkFallback: CanonicalSolidColor? = nil
    var isValid: Bool { blur.isFinite && (0...60).contains(blur) && fallback.isValid && fallback.alpha == 1 && (darkFallback.map { $0.isValid && $0.alpha == 1 } ?? true) }
    var properties: [String: PropertyValue] {
        var values: [String: PropertyValue] = [Self.namespace + "blur": .number(blur), Self.namespace + "fallback.red": .number(fallback.red),
         Self.namespace + "fallback.green": .number(fallback.green), Self.namespace + "fallback.blue": .number(fallback.blue),
         Self.namespace + "fallback.alpha": .number(fallback.alpha)]
        if let color = darkFallback {
            for (key, value) in [("red", color.red), ("green", color.green), ("blue", color.blue), ("alpha", color.alpha)] {
                values[Self.namespace + "darkFallback." + key] = .number(value)
            }
        }
        return values
    }
    static func resolve(_ node: DocumentNode) throws -> Self? {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix("style.glass.") }
        guard !owned.isEmpty else { return nil }
        var expected = Set(Self(blur: 16, fallback: .legacySurface).properties.keys)
        let hasDark = owned.contains { $0.key.rawValue.hasPrefix(namespace + "darkFallback.") }
        if hasDark { expected.formUnion(["red", "green", "blue", "alpha"].map { namespace + "darkFallback." + $0 }) }
        guard [.frame, .section, .stack, .grid, .button].contains(node.kind),
              Set(owned.map(\.key.rawValue)) == expected, owned.count == expected.count,
              let blur = node.insertionNumberProperty(namespace + "blur"),
              let red = node.insertionNumberProperty(namespace + "fallback.red"),
              let green = node.insertionNumberProperty(namespace + "fallback.green"),
              let blue = node.insertionNumberProperty(namespace + "fallback.blue"),
              let alpha = node.insertionNumberProperty(namespace + "fallback.alpha") else {
            throw ModelValidationError.invalidBoxStyleState
        }
        var result = Self(blur: blur, fallback: .init(red: red, green: green, blue: blue, alpha: alpha))
        if hasDark {
            guard let r = node.insertionNumberProperty(namespace + "darkFallback.red"), let g = node.insertionNumberProperty(namespace + "darkFallback.green"),
                  let b = node.insertionNumberProperty(namespace + "darkFallback.blue"), let a = node.insertionNumberProperty(namespace + "darkFallback.alpha")
            else { throw ModelValidationError.invalidBoxStyleState }
            result.darkFallback = .init(red: r, green: g, blue: b, alpha: a)
        }
        guard result.isValid else { throw ModelValidationError.invalidBoxStyleState }
        return result
    }
}


struct LocalColorToken: Codable, Equatable, Identifiable, Sendable {
    let id: ColorTokenID
    var name: String
    var color: CanonicalSolidColor
    var darkColor: CanonicalSolidColor?

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, name, color, darkColor }

    init(id: ColorTokenID = ColorTokenID(), name: String, color: CanonicalSolidColor, darkColor: CanonicalSolidColor? = nil) {
        self.id = id; self.name = name; self.color = color; self.darkColor = darkColor
    }

    init(from decoder: Decoder) throws {
        try requireKnownKeys(CodingKeys.self, in: decoder)
        let raw = try decoder.container(keyedBy: AnySiteForgeCodingKey.self)
        guard Set(["id", "name", "color"]).isSubset(of: Set(raw.allKeys.map(\.stringValue))),
              (decoder.userInfo[SiteForgeDecodingPolicy.sourceDocumentSchema] as? Int ?? 21) >= 21 || !raw.allKeys.contains(where: { $0.stringValue == "darkColor" })
        else { throw DocumentSerializationError.malformedInput }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(ColorTokenID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        color = try values.decode(CanonicalSolidColor.self, forKey: .color)
        darkColor = try values.decodeIfPresent(CanonicalSolidColor.self, forKey: .darkColor)
    }

    var isValid: Bool {
        !name.isEmpty && name == name.trimmingCharacters(in: .whitespacesAndNewlines)
            && name.utf8.count <= 128 && !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && color.isValid && (darkColor?.isValid ?? true)
    }
}

enum LocalColorTarget: String, CaseIterable, Sendable {
    case fill, border, outerShadow, textForeground
    /// Scene-local initial context only; never chooses a primary object's
    /// value or changes applicability/canonical token fallback semantics.
    static func initialInspectorTarget(for kinds: [NodeKind]) -> Self {
        !kinds.isEmpty && kinds.allSatisfy { $0 == .text } ? .textForeground : .fill
    }
    var displayName: String {
        switch self {
        case .fill: "Fill"
        case .border: "Border"
        case .outerShadow: "Outer Shadow"
        case .textForeground: "Text Foreground"
        }
    }
}

enum LocalColorTokenBinding {
    static let legacyKey = "style.fill.token.v1.id"
    // Retain the historical symbol for schema-nine fixtures only.
    static let key = legacyKey
    static let prefix = "style.color.token.v2."
    static func key(for target: LocalColorTarget) -> String { prefix + target.rawValue + ".id" }
    static func id(for node: DocumentNode, target: LocalColorTarget = .fill) -> ColorTokenID? {
        let current = node.insertionStringProperty(key(for: target)).flatMap(ColorTokenID.init(uuidString:))
        return current ?? (target == .fill ? node.insertionStringProperty(legacyKey).flatMap(ColorTokenID.init(uuidString:)) : nil)
    }

    static func validate(_ node: DocumentNode) throws {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix(prefix) || $0.key.rawValue == legacyKey }
        guard !owned.isEmpty else { return }
        guard !owned.contains(where: { $0.key.rawValue == legacyKey }),
              Set(owned.map(\.key)).count == owned.count,
              Set(owned.map { $0.key.rawValue }).isSubset(of: Set(LocalColorTarget.allCases.map { key(for: $0) })) else {
            throw ModelValidationError.invalidColorToken
        }
        for property in owned {
            guard let target = LocalColorTarget.allCases.first(where: { key(for: $0) == property.key.rawValue }),
                  case .string(let raw) = property.value, ColorTokenID(uuidString: raw) != nil else {
                throw ModelValidationError.invalidColorToken
            }
            switch target {
            case .fill:
                guard [.frame, .section, .stack, .grid].contains(node.kind) else { throw ModelValidationError.invalidColorToken }
            case .border:
                guard [.frame, .section, .stack, .grid, .button].contains(node.kind),
                      node.insertionProperty("style.box.v1.border.width") != nil else { throw ModelValidationError.invalidColorToken }
            case .outerShadow:
                guard [.frame, .section, .stack, .grid, .button].contains(node.kind),
                      node.insertionProperty("style.box.v1.shadow.offsetX") != nil else { throw ModelValidationError.invalidColorToken }
            case .textForeground:
                guard node.kind.isTextual, CanonicalTextForeground.literal(for: node) != nil else {
                    throw ModelValidationError.invalidColorToken
                }
            }
        }
    }
}

/// Base-only fixed sizing policy. Omitted properties mean unconstrained;
/// authored values retain their NodeProperty identity and origin.
enum SizingDimension: String, CaseIterable, Sendable { case width, height }
enum CanonicalSizingMode: String, CaseIterable, Sendable { case fixed, fill, hug }

struct SizingDimensionResolution: Equatable, Sendable {
    let declaredMode: CanonicalSizingMode
    let effectiveMode: CanonicalSizingMode
    let modeOrigin: PropertyOrigin?
    let numericSource: ResponsiveGeometrySource?
}

struct CanonicalSizingConstraints: Equatable, Sendable {
    static let prefix = "layout.sizing.v1."
    static let maximum = 100_000.0
    static let minimumRatio = 0.01
    static let maximumRatio = 100.0
    var minWidth: Double?
    var minHeight: Double?
    var maxWidth: Double?
    var maxHeight: Double?
    var aspectRatio: Double?
    var aspectEnabled: Bool
    var widthMode: CanonicalSizingMode = .fixed
    var heightMode: CanonicalSizingMode = .fixed
    static let supportedKinds: Set<NodeKind> = [.frame, .image, .text, .section, .stack, .grid, .button, .link]
    static let boundsSupportedKinds: Set<NodeKind> = [.frame, .image, .section, .stack, .grid]

    func mode(_ dimension: SizingDimension) -> CanonicalSizingMode {
        dimension == .width ? widthMode : heightMode
    }

    static func isLayoutResolved(_ field: GeometryInspectorField, node: DocumentNode,
        page: DocumentPage, breakpoint: ResponsiveBreakpoint, width: Double?,
        nodesByID: [NodeID: DocumentNode]? = nil) -> Bool {
        switch field {
        case .width: return effectiveMode(.width, node: node, breakpoint: breakpoint, width: width) != .fixed
        case .height: return effectiveMode(.height, node: node, breakpoint: breakpoint, width: width) != .fixed
        case .x, .y:
            if field == .x, effectiveMode(.width, node: node, breakpoint: breakpoint, width: width) == .fill { return true }
            if field == .y, effectiveMode(.height, node: node, breakpoint: breakpoint, width: width) == .fill { return true }
            let byID = nodesByID ?? Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
            var parent = node.parent, visited = Set<NodeID>()
            while case .node(let id) = parent, visited.insert(id).inserted, let ancestor = byID[id] {
                // OD-018: a copy's slot contents are placed within its slot,
                // never by layout outside the copy.
                if ancestor.kind == .component { break }
                let value = resolved(for: ancestor)
                if value.widthMode != .fixed || value.heightMode != .fixed { return true }
                parent = ancestor.parent
            }
            return false
        }
    }

    static func effectiveMode(_ dimension: SizingDimension, node: DocumentNode,
                              breakpoint: ResponsiveBreakpoint, width: Double?) -> CanonicalSizingMode {
        dimensionResolution(dimension, node: node, breakpoint: breakpoint, width: width).effectiveMode
    }

    /// Inspector and layout report the same winner. A declared automatic mode
    /// remains authored intent when a deliberate numeric dimension takes over.
    static func dimensionResolution(_ dimension: SizingDimension, node: DocumentNode,
                                    breakpoint: ResponsiveBreakpoint, width: Double?) -> SizingDimensionResolution {
        let field: GeometryInspectorField = dimension == .width ? .width : .height
        let fluidTarget: FluidValueTarget = dimension == .width ? .width : .height
        let mode = resolved(for: node).mode(dimension)
        let origin = node.insertionProperty(prefix + dimension.rawValue + "Mode")?.origin
        let source = ResponsiveGeometryResolver.value(for: field, node: node,
            breakpoint: breakpoint, viewportWidth: width)?.2
        let winner: ResponsiveGeometrySource?
        if case .override = source { winner = source }
        else if CanonicalFluidValueCodec.value(for: fluidTarget, node: node) != nil { winner = .fluid }
        else { winner = nil }
        return .init(declaredMode: mode, effectiveMode: winner == nil ? mode : .fixed,
            modeOrigin: origin, numericSource: winner)
    }

    static let unconstrained = Self(minWidth: nil, minHeight: nil,
        maxWidth: nil, maxHeight: nil, aspectRatio: nil, aspectEnabled: false)

    static func resolved(for node: DocumentNode) -> Self {
        let number: (String) -> Double? = { node.insertionNumberProperty(prefix + $0) }
        return .init(minWidth: number("minWidth"), minHeight: number("minHeight"),
            maxWidth: number("maxWidth"), maxHeight: number("maxHeight"),
            aspectRatio: number("aspectRatio"),
            aspectEnabled: node.insertionBooleanProperty(prefix + "aspectEnabled"),
            widthMode: node.insertionStringProperty(prefix + "widthMode").flatMap(CanonicalSizingMode.init(rawValue:)) ?? .fixed,
            heightMode: node.insertionStringProperty(prefix + "heightMode").flatMap(CanonicalSizingMode.init(rawValue:)) ?? .fixed)
    }

    var isValid: Bool {
        guard widthMode != .hug,
              !aspectEnabled || (widthMode == .fixed && heightMode == .fixed) else { return false }
        let bounds = [minWidth, minHeight, maxWidth, maxHeight].compactMap { $0 }
        guard bounds.allSatisfy({ $0.isFinite && (0...Self.maximum).contains($0) }),
              maxWidth.map({ $0 >= 1 }) ?? true,
              maxHeight.map({ $0 >= 1 }) ?? true,
              minWidth.map({ $0 <= (maxWidth ?? Self.maximum) }) ?? true,
              minHeight.map({ $0 <= (maxHeight ?? Self.maximum) }) ?? true else { return false }
        if let aspectRatio {
            guard aspectRatio.isFinite,
                  (Self.minimumRatio...Self.maximumRatio).contains(aspectRatio) else { return false }
        }
        guard !aspectEnabled || aspectRatio != nil else { return false }
        if aspectEnabled, let ratio = aspectRatio {
            let lowerWidth = max(max(1, minWidth ?? 1), max(1, minHeight ?? 1) * ratio)
            let upperWidth = min(min(Self.maximum, maxWidth ?? Self.maximum),
                (maxHeight ?? Self.maximum) * ratio)
            return lowerWidth <= upperWidth
        }
        return true
    }
}

enum CanonicalSizingNamespaceValidator {
    static func validate(_ node: DocumentNode) throws {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix(CanonicalSizingConstraints.prefix) }
        guard !owned.isEmpty else { return }
        guard CanonicalSizingConstraints.supportedKinds.contains(node.kind) else { throw ModelValidationError.invalidSizingConstraints }
        let keys = owned.map { String($0.key.rawValue.dropFirst(CanonicalSizingConstraints.prefix.count)) }
        guard Set(keys).count == keys.count,
              Set(keys).isSubset(of: ["minWidth", "minHeight", "maxWidth", "maxHeight", "aspectRatio", "aspectEnabled", "widthMode", "heightMode"]) else {
            throw ModelValidationError.invalidSizingConstraints
        }
        for property in owned {
            if ["widthMode", "heightMode"].contains(String(property.key.rawValue.dropFirst(CanonicalSizingConstraints.prefix.count))) {
                guard case .string(let raw) = property.value, CanonicalSizingMode(rawValue: raw) != nil else {
                    throw ModelValidationError.invalidSizingConstraints
                }
            } else if property.key.rawValue == CanonicalSizingConstraints.prefix + "aspectEnabled" {
                guard boundsSupportedKindsContain(node.kind) else { throw ModelValidationError.invalidSizingConstraints }
                guard case .boolean = property.value else { throw ModelValidationError.invalidSizingConstraints }
            } else {
                guard boundsSupportedKindsContain(node.kind) else { throw ModelValidationError.invalidSizingConstraints }
                guard case .number = property.value else { throw ModelValidationError.invalidSizingConstraints }
            }
        }
        let sizing = CanonicalSizingConstraints.resolved(for: node)
        guard sizing.isValid,
              node.kind != .image || sizing.heightMode != .hug else { throw ModelValidationError.invalidSizingConstraints }
    }

    private static func boundsSupportedKindsContain(_ kind: NodeKind) -> Bool {
        CanonicalSizingConstraints.boundsSupportedKinds.contains(kind)
    }
}

/// `svg` (SF-0804, OD-045) is a sanitized vector image rendered as an image;
/// it needs document schema 27.
enum ImageAssetFormat: String, Codable, CaseIterable, Sendable {
    case png, jpeg, gif, tiff, heic, svg

    var mediaType: String {
        switch self {
        case .png: "image/png"
        case .jpeg: "image/jpeg"
        case .gif: "image/gif"
        case .tiff: "image/tiff"
        case .heic: "image/heic"
        case .svg: "image/svg+xml"
        }
    }
}

enum ImageAssetProvenance: String, Codable, Sendable {
    case imported
}

/// Project-local grouping only. No segment denotes a filesystem location.
struct AssetOrganization: Codable, Equatable, Sendable {
    static let version = 1
    static let maximumTags = 12
    let version: Int
    var folderPath: String?
    var tags: [String]
    var favorite: Bool

    init(folderPath: String? = nil, tags: [String] = [], favorite: Bool = false) throws {
        version = Self.version
        self.folderPath = try Self.normalizedFolder(folderPath)
        self.tags = try Self.normalizedTags(tags)
        self.favorite = favorite
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case version, folderPath, tags, favorite }
    init(from decoder: Decoder) throws {
        if SiteForgeDecodingPolicy.requiresExactKeys(decoder) {
            try requireKnownKeys(CodingKeys.self, in: decoder)
            let raw = try decoder.container(keyedBy: AnySiteForgeCodingKey.self)
            let present = Set(raw.allKeys.map(\.stringValue))
            guard Set(["version", "tags", "favorite"]).isSubset(of: present) else {
                throw ModelValidationError.invalidImageAsset
            }
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        folderPath = try values.decodeIfPresent(String.self, forKey: .folderPath)
        tags = try values.decode([String].self, forKey: .tags)
        favorite = try values.decode(Bool.self, forKey: .favorite)
        guard isValid else { throw ModelValidationError.invalidImageAsset }
    }

    var isValid: Bool {
        version == Self.version
            && (try? Self.normalizedFolder(folderPath)) == folderPath
            && (try? Self.normalizedTags(tags)) == tags
    }

    var isEmpty: Bool { folderPath == nil && tags.isEmpty && !favorite }

    static func normalizedFolder(_ input: String?) throws -> String? {
        guard let input, !input.isEmpty else { return nil }
        let segments = input.precomposedStringWithCanonicalMapping.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard (1...4).contains(segments.count), segments.allSatisfy({ validSegment($0, maximumBytes: 40) }) else {
            throw ModelValidationError.invalidImageAsset
        }
        return segments.joined(separator: "/")
    }

    static func normalizedTags(_ input: [String]) throws -> [String] {
        guard input.count <= maximumTags else { throw ModelValidationError.invalidImageAsset }
        let normalized = input.map { $0.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard normalized.allSatisfy({ validSegment($0, maximumBytes: 32) }),
              Set(normalized.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }).count == normalized.count else {
            throw ModelValidationError.invalidImageAsset
        }
        return normalized.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    private static func validSegment(_ value: String, maximumBytes: Int) -> Bool {
        !value.isEmpty && value != "." && value != ".." && value.utf8.count <= maximumBytes
            && !value.contains("/") && !value.contains("\\")
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
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
    var organization: AssetOrganization?

    init(
        id: AssetID = AssetID(), resourceID: ResourceID,
        displayName: String, originalFilename: String,
        format: ImageAssetFormat, pixelWidth: Int, pixelHeight: Int,
        byteCount: Int, contentHash: String,
        provenance: ImageAssetProvenance = .imported,
        organization: AssetOrganization? = nil
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
        self.organization = organization
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, resourceID, displayName, originalFilename, format, pixelWidth,
             pixelHeight, byteCount, contentHash, provenance, organization
    }

    init(from decoder: Decoder) throws {
        if SiteForgeDecodingPolicy.requiresExactKeys(decoder) {
            try requireKnownKeys(CodingKeys.self, in: decoder)
            let raw = try decoder.container(keyedBy: AnySiteForgeCodingKey.self)
            let present = Set(raw.allKeys.map(\.stringValue))
            let required = Set(CodingKeys.allCases.map(\.stringValue)).subtracting([CodingKeys.organization.rawValue])
            guard required.isSubset(of: present) else { throw ModelValidationError.invalidImageAsset }
        }
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
        organization = try container.decodeIfPresent(AssetOrganization.self, forKey: .organization)
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
              contentHash.allSatisfy(\.isHexDigit),
              organization?.isValid != false else {
            throw ModelValidationError.invalidImageAsset
        }
    }
}

// MARK: - SF-0805 project fonts (OD-045, ADR-0051)

/// Project-embedded font files. No font service, no installed-font copying.
enum FontAssetFormat: String, Codable, CaseIterable, Sendable {
    case woff2, ttf

    var mediaType: String {
        switch self {
        case .woff2: "font/woff2"
        case .ttf: "font/ttf"
        }
    }

    /// The CSS `format()` hint.
    var cssFormat: String {
        switch self {
        case .woff2: "woff2"
        case .ttf: "truetype"
        }
    }
}

enum FontFaceStyle: String, Codable, CaseIterable, Sendable {
    case normal, italic
}

/// System-font fallback stacks written after the project family.
enum FontFallbackStack: String, Codable, CaseIterable, Sendable {
    case sansSerif, serif, monospace

    var title: String {
        switch self {
        case .sansSerif: "System sans-serif"
        case .serif: "System serif"
        case .monospace: "System monospace"
        }
    }

    var css: String {
        switch self {
        case .sansSerif: "system-ui, -apple-system, \"Helvetica Neue\", Arial, sans-serif"
        case .serif: "ui-serif, Georgia, \"Times New Roman\", serif"
        case .monospace: "ui-monospace, Menlo, Consolas, monospace"
        }
    }
}

/// Declared by the author. Only `webEmbeddingAllowed` faces are ever copied
/// into website output (SF-0805: never redistributed contrary to declared
/// rights); a new import starts `unconfirmed` (or `editorOnly` when the file
/// itself declares restricted embedding).
enum FontEmbeddingRights: String, Codable, CaseIterable, Sendable {
    case unconfirmed, webEmbeddingAllowed, editorOnly

    var title: String {
        switch self {
        case .unconfirmed: "Not confirmed (not exported)"
        case .webEmbeddingAllowed: "License allows web embedding"
        case .editorOnly: "Editing only (not exported)"
        }
    }

    var allowsWebExport: Bool { self == .webEmbeddingAllowed }
}

/// One font face. Original bytes stay in the content-addressed resource store,
/// like image assets; canonical state never keeps a path.
struct FontAsset: Codable, Equatable, Identifiable, Sendable {
    static let maximumAssetCount = 200
    static let maximumFamilyBytes = 128
    static let maximumLicenseNoteBytes = 4_096
    static let maximumOriginalFilenameBytes = 1_024
    static let allowedWeights = Array(stride(from: 100, through: 900, by: 100))
    /// Stored from document schema 27 (unreleased).
    static let documentSchema = 27

    let id: AssetID
    var resourceID: ResourceID
    var family: String
    var weight: Int
    var style: FontFaceStyle
    var format: FontAssetFormat
    var originalFilename: String
    var byteCount: Int
    var contentHash: String
    var rights: FontEmbeddingRights
    /// Omitted when not written; never stored as null or blank.
    var licenseNote: String?
    var fallback: FontFallbackStack

    init(
        id: AssetID = AssetID(), resourceID: ResourceID, family: String, weight: Int = 400,
        style: FontFaceStyle = .normal, format: FontAssetFormat, originalFilename: String,
        byteCount: Int, contentHash: String, rights: FontEmbeddingRights = .unconfirmed,
        licenseNote: String? = nil, fallback: FontFallbackStack = .sansSerif
    ) {
        self.id = id
        self.resourceID = resourceID
        self.family = family
        self.weight = weight
        self.style = style
        self.format = format
        self.originalFilename = originalFilename
        self.byteCount = byteCount
        self.contentHash = contentHash
        self.rights = rights
        self.licenseNote = licenseNote
        self.fallback = fallback
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, resourceID, family, weight, style, format, originalFilename, byteCount, contentHash,
             rights, licenseNote, fallback
    }

    init(from decoder: Decoder) throws {
        if SiteForgeDecodingPolicy.requiresExactKeys(decoder) {
            try requireKnownKeys(CodingKeys.self, in: decoder)
            let raw = try decoder.container(keyedBy: AnySiteForgeCodingKey.self)
            let present = Set(raw.allKeys.map(\.stringValue))
            let required = Set(CodingKeys.allCases.map(\.stringValue)).subtracting([CodingKeys.licenseNote.rawValue])
            guard required.isSubset(of: present) else { throw ModelValidationError.invalidFontAsset }
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(AssetID.self, forKey: .id)
        resourceID = try container.decode(ResourceID.self, forKey: .resourceID)
        family = try container.decode(String.self, forKey: .family)
        weight = try container.decode(Int.self, forKey: .weight)
        style = try container.decode(FontFaceStyle.self, forKey: .style)
        format = try container.decode(FontAssetFormat.self, forKey: .format)
        originalFilename = try container.decode(String.self, forKey: .originalFilename)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        contentHash = try container.decode(String.self, forKey: .contentHash)
        rights = try container.decode(FontEmbeddingRights.self, forKey: .rights)
        if container.contains(.licenseNote), try container.decodeNil(forKey: .licenseNote) {
            throw ModelValidationError.invalidFontAsset
        }
        licenseNote = try container.decodeIfPresent(String.self, forKey: .licenseNote)
        fallback = try container.decode(FontFallbackStack.self, forKey: .fallback)
    }

    static func isValidFamily(_ family: String) -> Bool {
        let trimmed = family.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed == family && family.utf8.count <= maximumFamilyBytes
            && family.rangeOfCharacter(from: .controlCharacters) == nil
            && family.caseInsensitiveCompare(CanonicalTypography.defaultFamily) != .orderedSame
    }

    var isValid: Bool {
        let noteIsValid = licenseNote.map {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.utf8.count <= Self.maximumLicenseNoteBytes && !$0.contains("\u{0}")
        } ?? true
        return Self.isValidFamily(family) && Self.allowedWeights.contains(weight) && noteIsValid
            && !originalFilename.isEmpty && originalFilename.utf8.count <= Self.maximumOriginalFilenameBytes
            && !originalFilename.contains("/") && !originalFilename.contains("\\")
            && byteCount > 0 && byteCount <= ImageAsset.maximumResourceBytes
            && contentHash.count == 64 && contentHash == contentHash.lowercased()
            && contentHash.allSatisfy(\.isHexDigit)
    }

    /// Two faces may not share family (case-insensitive), weight and style.
    var faceKey: String { "\(family.lowercased())|\(weight)|\(style.rawValue)" }

    func validate() throws {
        guard isValid else { throw ModelValidationError.invalidFontAsset }
    }

    static func validate(_ fonts: [FontAsset]) throws {
        guard fonts.count <= maximumAssetCount,
              Set(fonts.map(\.id)).count == fonts.count,
              Set(fonts.map(\.resourceID)).count == fonts.count,
              Set(fonts.map(\.contentHash)).count == fonts.count,
              Set(fonts.map(\.faceKey)).count == fonts.count else {
            throw ModelValidationError.invalidFontAsset
        }
        for font in fonts { try font.validate() }
    }
}

/// SF-0805-003: which face a text style gets, and why. CSS Fonts 4 matching:
/// style first (italic falls back to normal and back), then weight — for a
/// desired 400–500 try heavier up to 500, then lighter, then heavier; below
/// 400 lighter first; above 500 heavier first.
enum ProjectFontResolver {
    struct Resolution: Equatable, Sendable {
        enum Rule: String, Equatable, Sendable { case notProjectFont, exactFace, nearestFace }
        let rule: Rule
        let face: FontAsset?
        /// The family's fallback stack: its lightest face (then style, then
        /// stable identity) decides.
        let fallback: FontFallbackStack?
        let explanation: String
    }

    static func cssWeight(_ weight: CanonicalFontWeight) -> Int {
        switch weight {
        case .regular: 400
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        }
    }

    static func faces(family: String, in fonts: [FontAsset]) -> [FontAsset] {
        fonts.filter { $0.family.caseInsensitiveCompare(family) == .orderedSame }
            .sorted { ($0.weight, $0.style.rawValue, $0.id.description) < ($1.weight, $1.style.rawValue, $1.id.description) }
    }

    /// Distinct families in display order (first spelling wins).
    static func families(in fonts: [FontAsset]) -> [String] {
        var seen = Set<String>(), result: [String] = []
        for font in fonts.sorted(by: { $0.family.lowercased() < $1.family.lowercased() })
        where seen.insert(font.family.lowercased()).inserted {
            result.append(font.family)
        }
        return result
    }

    static func fallback(family: String, in fonts: [FontAsset]) -> FontFallbackStack? {
        faces(family: family, in: fonts).first?.fallback
    }

    static func nearestWeight(_ desired: Int, among weights: [Int]) -> Int? {
        guard !weights.isEmpty else { return nil }
        if weights.contains(desired) { return desired }
        let lighter = weights.filter { $0 < desired }.sorted(by: >)
        let heavier = weights.filter { $0 > desired }.sorted()
        if (400...500).contains(desired) {
            if let up = heavier.first(where: { $0 <= 500 }) { return up }
            return lighter.first ?? heavier.first
        }
        if desired < 400 { return lighter.first ?? heavier.first }
        return heavier.first ?? lighter.first
    }

    static func resolve(family: String, weight: Int, italic: Bool = false, in fonts: [FontAsset]) -> Resolution {
        let all = faces(family: family, in: fonts)
        guard !all.isEmpty else {
            return .init(rule: .notProjectFont, face: nil, fallback: nil,
                         explanation: "Not a project font: an installed font with this name is used, otherwise the system font.")
        }
        let wanted: FontFaceStyle = italic ? .italic : .normal
        let sameStyle = all.filter { $0.style == wanted }
        let candidates = sameStyle.isEmpty ? all : sameStyle
        let chosenWeight = nearestWeight(weight, among: candidates.map(\.weight)) ?? weight
        let face = candidates.first { $0.weight == chosenWeight }
        let fallback = all.first?.fallback
        if let face, face.weight == weight, face.style == wanted {
            return .init(rule: .exactFace, face: face, fallback: fallback,
                         explanation: "Project font face \(face.weight) \(face.style.rawValue) matches exactly.")
        }
        let shown = face.map { "\($0.weight) \($0.style.rawValue)" } ?? "none"
        return .init(rule: .nearestFace, face: face, fallback: fallback,
                     explanation: "No \(weight) \(wanted.rawValue) face in the project; browsers use the nearest face (\(shown)) and may synthesize the rest. Import that face to match exactly.")
    }

    /// Text nodes (all pages, including component definitions) using a family.
    static func usageCount(family: String, in document: CanonicalDocument) -> Int {
        document.pages.flatMap(\.nodes).filter {
            CanonicalTypography.resolved(for: $0)?.family.caseInsensitiveCompare(family) == .orderedSame
        }.count
    }
}

/// SF-0805-002/005: the one way the UI changes the project's fonts.
enum FontAssetEditing {
    static func prepare(_ fonts: [FontAsset], document: CanonicalDocument) throws -> DocumentCommand {
        try FontAsset.validate(fonts)
        guard fonts != document.fontAssets else {
            throw CommandExecutionError.disabled("The project fonts are unchanged.")
        }
        return .setFontAssets(SetFontAssetsCommand(documentID: document.id, fontAssets: fonts))
    }
}

// MARK: - SF-0803 video and audio (OD-045, ADR-0100)

/// What a project media file is used for.
enum MediaAssetKind: String, Codable, CaseIterable, Sendable {
    case video, audio, captions

    var title: String {
        switch self {
        case .video: "Video"
        case .audio: "Audio"
        case .captions: "Captions"
        }
    }
}

/// Local media formats that browsers play natively. Files are never
/// transcoded: the original bytes are kept and copied into the website.
enum MediaAssetFormat: String, Codable, CaseIterable, Sendable {
    case mp4, webm, mp3, m4a, ogg, wav, vtt

    var kind: MediaAssetKind {
        switch self {
        case .mp4, .webm: .video
        case .mp3, .m4a, .ogg, .wav: .audio
        case .vtt: .captions
        }
    }

    var mediaType: String {
        switch self {
        case .mp4: "video/mp4"
        case .webm: "video/webm"
        case .mp3: "audio/mpeg"
        case .m4a: "audio/mp4"
        case .ogg: "audio/ogg"
        case .wav: "audio/wav"
        case .vtt: "text/vtt"
        }
    }

    /// Extension of the content-addressed output file (`assets/<sha>.<ext>`).
    var fileExtension: String { rawValue }
}

/// One project video, audio or captions (WebVTT) file. Original bytes stay in
/// the content-addressed resource store, like images and fonts; canonical
/// state never keeps a path.
struct MediaAsset: Codable, Equatable, Identifiable, Sendable {
    static let maximumAssetCount = 500
    static let maximumDisplayNameBytes = 1_024
    static let maximumOriginalFilenameBytes = 1_024
    static let maximumLanguageBytes = 35
    /// Stored from document schema 27 (unreleased).
    static let documentSchema = 27

    let id: AssetID
    var resourceID: ResourceID
    var displayName: String
    var originalFilename: String
    var format: MediaAssetFormat
    var byteCount: Int
    var contentHash: String
    /// Captions only: the cue language as a BCP 47 tag (`en`, `pt-BR`).
    /// Omitted when not set; never stored as null or blank.
    var language: String?

    init(
        id: AssetID = AssetID(), resourceID: ResourceID, displayName: String, originalFilename: String,
        format: MediaAssetFormat, byteCount: Int, contentHash: String, language: String? = nil
    ) {
        self.id = id
        self.resourceID = resourceID
        self.displayName = displayName
        self.originalFilename = originalFilename
        self.format = format
        self.byteCount = byteCount
        self.contentHash = contentHash
        self.language = language
    }

    var kind: MediaAssetKind { format.kind }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, resourceID, displayName, originalFilename, format, byteCount, contentHash, language
    }

    init(from decoder: Decoder) throws {
        if SiteForgeDecodingPolicy.requiresExactKeys(decoder) {
            try requireKnownKeys(CodingKeys.self, in: decoder)
            let raw = try decoder.container(keyedBy: AnySiteForgeCodingKey.self)
            let present = Set(raw.allKeys.map(\.stringValue))
            let required = Set(CodingKeys.allCases.map(\.stringValue)).subtracting([CodingKeys.language.rawValue])
            guard required.isSubset(of: present) else { throw ModelValidationError.invalidMediaAsset }
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(AssetID.self, forKey: .id)
        resourceID = try container.decode(ResourceID.self, forKey: .resourceID)
        displayName = try container.decode(String.self, forKey: .displayName)
        originalFilename = try container.decode(String.self, forKey: .originalFilename)
        format = try container.decode(MediaAssetFormat.self, forKey: .format)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        contentHash = try container.decode(String.self, forKey: .contentHash)
        if container.contains(.language), try container.decodeNil(forKey: .language) {
            throw ModelValidationError.invalidMediaAsset
        }
        language = try container.decodeIfPresent(String.self, forKey: .language)
    }

    static func isValidLanguage(_ value: String) -> Bool {
        value.utf8.count <= maximumLanguageBytes
            && value.range(of: "^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$", options: .regularExpression) != nil
    }

    var isValid: Bool {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let languageIsValid = language.map { format == .vtt && Self.isValidLanguage($0) } ?? true
        return !trimmed.isEmpty && displayName.utf8.count <= Self.maximumDisplayNameBytes
            && !displayName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && !originalFilename.isEmpty && originalFilename.utf8.count <= Self.maximumOriginalFilenameBytes
            && !originalFilename.contains("/") && !originalFilename.contains("\\")
            && byteCount > 0 && byteCount <= ImageAsset.maximumResourceBytes
            && contentHash.count == 64 && contentHash == contentHash.lowercased()
            && contentHash.allSatisfy(\.isHexDigit) && languageIsValid
    }

    func validate() throws {
        guard isValid else { throw ModelValidationError.invalidMediaAsset }
    }

    static func validate(_ media: [MediaAsset]) throws {
        guard media.count <= maximumAssetCount,
              Set(media.map(\.id)).count == media.count,
              Set(media.map(\.resourceID)).count == media.count,
              Set(media.map(\.contentHash)).count == media.count else {
            throw ModelValidationError.invalidMediaAsset
        }
        for asset in media { try asset.validate() }
    }
}

/// SF-0803-001/003: an Image node in media mode plays a project video or
/// audio file. The Image's own image is the video's poster (and, for audio,
/// what the canvas shows). Controls are always the browser's native controls.
/// An absent setting means its default (off); an authored `false` stays
/// authored, so omitted, defaulted and authored values stay distinct.
struct CanonicalMediaPlayback: Equatable, Sendable {
    static let namespace = "content.media.v1."
    static let assetKey = namespace + "assetID"
    static let captionsKey = namespace + "captionsAssetID"

    enum Setting: String, CaseIterable, Sendable {
        case loop, muted, autoplay

        var key: String { CanonicalMediaPlayback.namespace + rawValue }

        var title: String {
            switch self {
            case .loop: "Loop"
            case .muted: "Start muted"
            case .autoplay: "Autoplay (muted video only)"
            }
        }
    }

    static var keys: Set<String> { Set([assetKey, captionsKey] + Setting.allCases.map(\.key)) }

    var assetID: AssetID
    var captionsAssetID: AssetID?
    /// `nil` means not authored (default off).
    var loop: Bool?
    var muted: Bool?
    var autoplay: Bool?

    init(assetID: AssetID, captionsAssetID: AssetID? = nil, loop: Bool? = nil, muted: Bool? = nil, autoplay: Bool? = nil) {
        self.assetID = assetID
        self.captionsAssetID = captionsAssetID
        self.loop = loop
        self.muted = muted
        self.autoplay = autoplay
    }

    var loops: Bool { loop ?? false }
    var isMuted: Bool { muted ?? false }
    var autoplays: Bool { autoplay ?? false }

    func value(_ setting: Setting) -> Bool? {
        switch setting {
        case .loop: loop
        case .muted: muted
        case .autoplay: autoplay
        }
    }

    static func resolve(_ node: DocumentNode) -> CanonicalMediaPlayback? {
        guard node.kind == .image,
              let raw = node.insertionStringProperty(assetKey),
              let id = AssetID(uuidString: raw) else { return nil }
        func flag(_ setting: Setting) -> Bool? {
            guard case .boolean(let value)? = node.insertionProperty(setting.key)?.value else { return nil }
            return value
        }
        let captions = node.insertionStringProperty(captionsKey).flatMap { AssetID(uuidString: $0) }
        return .init(assetID: id, captionsAssetID: captions, loop: flag(.loop), muted: flag(.muted), autoplay: flag(.autoplay))
    }

    /// Closed key set; the file must exist and be video or audio; captions
    /// only for video; sound never starts by itself (autoplay only for muted
    /// video).
    static func validate(_ node: DocumentNode, media: [AssetID: MediaAsset]) throws {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix(namespace) }
        guard !owned.isEmpty else { return }
        guard node.kind == .image, Set(owned.map(\.key.rawValue)).isSubset(of: keys),
              case .string(let raw)? = node.insertionProperty(assetKey)?.value,
              let id = AssetID(uuidString: raw), let asset = media[id], asset.kind != .captions else {
            throw ModelValidationError.invalidMediaPlayback
        }
        for setting in Setting.allCases {
            if let property = node.insertionProperty(setting.key) {
                guard case .boolean = property.value else { throw ModelValidationError.invalidMediaPlayback }
            }
        }
        if let captions = node.insertionProperty(captionsKey) {
            guard asset.kind == .video, case .string(let rawCaptions) = captions.value,
                  let captionsID = AssetID(uuidString: rawCaptions), media[captionsID]?.kind == .captions else {
                throw ModelValidationError.invalidMediaPlayback
            }
        }
        guard let playback = resolve(node) else { throw ModelValidationError.invalidMediaPlayback }
        if playback.autoplays {
            guard asset.kind == .video, playback.isMuted else { throw ModelValidationError.invalidMediaPlayback }
        }
    }

    /// Paste into another project: playback whose file the destination does
    /// not have is dropped (the Image and its poster stay); a missing captions
    /// file drops only the captions.
    static func keepingAvailable(_ properties: [NodeProperty], mediaIDs: Set<AssetID>) -> [NodeProperty] {
        func reference(_ key: String) -> AssetID? {
            guard let property = properties.first(where: { $0.key.rawValue == key }),
                  case .string(let raw) = property.value else { return nil }
            return AssetID(uuidString: raw)
        }
        let mainAvailable = reference(assetKey).map { mediaIDs.contains($0) } ?? false
        let captionsAvailable = reference(captionsKey).map { mediaIDs.contains($0) } ?? false
        return properties.filter { property in
            let key = property.key.rawValue
            guard key.hasPrefix(namespace) else { return true }
            guard mainAvailable else { return false }
            return key != captionsKey || captionsAvailable
        }
    }

    /// SF-0803-003: which rule decides a setting.
    func provenance(_ setting: Setting) -> String {
        guard let authored = value(setting) else { return "Off (default)" }
        return authored ? "On (set on this Image)" : "Off (set on this Image)"
    }

    /// SF-0803-003: what the website gets and why. No file names or text.
    static func explanation(_ playback: CanonicalMediaPlayback, media: MediaAsset?) -> String {
        guard let media else {
            return "The video or audio file is not in the project; the website shows only the Image."
        }
        switch media.kind {
        case .video:
            var parts = ["Video with the browser's own controls; the Image is its poster until it plays."]
            parts.append(playback.autoplays ? "It starts by itself without sound (muted autoplay)." : "It starts only when the visitor presses Play.")
            if playback.captionsAssetID != nil { parts.append("Captions are offered and on by default.") }
            return parts.joined(separator: " ")
        case .audio:
            return "Audio with the browser's own controls. The Image shows only on the canvas; audio never starts by itself."
        case .captions:
            return "A captions file can't be played by itself. Choose a video or audio file."
        }
    }
}

/// SF-0803-002/005: the one way the UI changes an Image's playback, as one
/// grouped undoable edit. `nil` leaves media mode; the Image and its poster stay.
enum MediaPlaybackEditing {
    static func prepare(_ playback: CanonicalMediaPlayback?, nodeID: NodeID, pageID: PageID,
                        document: CanonicalDocument) throws -> DocumentCommand {
        guard let page = document.pages.first(where: { $0.id == pageID }),
              let node = page.nodes.first(where: { $0.id == nodeID }), node.kind == .image else {
            throw CommandExecutionError.disabled("Select one Image to give it a video or audio file.")
        }
        var wanted: [String: PropertyValue] = [:]
        if let playback {
            wanted[CanonicalMediaPlayback.assetKey] = .string(playback.assetID.description)
            if let captions = playback.captionsAssetID {
                wanted[CanonicalMediaPlayback.captionsKey] = .string(captions.description)
            }
            for setting in CanonicalMediaPlayback.Setting.allCases {
                if let value = playback.value(setting) { wanted[setting.key] = .boolean(value) }
            }
        }
        var commands: [DocumentCommand] = []
        for property in node.properties where property.key.rawValue.hasPrefix(CanonicalMediaPlayback.namespace)
            && wanted[property.key.rawValue] == nil {
            commands.append(.removeProperty(.init(pageID: pageID, nodeID: nodeID, propertyID: property.id)))
        }
        for key in wanted.keys.sorted() {
            guard let value = wanted[key] else { continue }
            let previous = node.insertionProperty(key)
            if previous?.value == value, previous?.origin == .authored { continue }
            commands.append(.setProperty(.init(pageID: pageID, nodeID: nodeID, property: NodeProperty(
                id: previous?.id ?? PropertyID(), key: .init(rawValue: key), value: value, origin: .authored))))
        }
        guard !commands.isEmpty else {
            throw CommandExecutionError.disabled("The video or audio settings are unchanged.")
        }
        let command: DocumentCommand = commands.count == 1 ? commands[0] : .batch(commands)
        let registry = CommandRegistry()
        if case .disabled(let reason) = registry.availability(for: command, in: document) {
            throw CommandExecutionError.disabled(reason)
        }
        // A single property edit's availability does not validate the result
        // (only grouped edits do), so the playback rules are checked on a
        // draft: a one-property change to audio with captions is refused too.
        var draft = document
        _ = try registry.apply(command, to: &draft)
        do { try draft.validate() } catch let error as ModelValidationError {
            throw CommandExecutionError.disabled(error.localizedDescription)
        }
        return command
    }
}

/// SF-0803-002/005: the one way the UI changes the project's media files.
/// A file that an Image still plays cannot be removed.
enum MediaAssetEditing {
    static func prepare(_ media: [MediaAsset], document: CanonicalDocument) throws -> DocumentCommand {
        try MediaAsset.validate(media)
        guard media != document.mediaAssets else {
            throw CommandExecutionError.disabled("The project's video and audio files are unchanged.")
        }
        let kept = Set(media.map(\.id))
        guard document.mediaAssets.allSatisfy({ kept.contains($0.id) || usageCount($0.id, in: document) == 0 }) else {
            throw CommandExecutionError.disabled("A file that an Image still plays can't be removed. Turn off its video or audio on each Image first.")
        }
        return .setMediaAssets(SetMediaAssetsCommand(documentID: document.id, mediaAssets: media))
    }

    /// Image nodes (all pages, including component definitions) that play or
    /// caption with this file.
    static func usageCount(_ id: AssetID, in document: CanonicalDocument) -> Int {
        document.pages.flatMap(\.nodes).filter { node in
            guard let playback = CanonicalMediaPlayback.resolve(node) else { return false }
            return playback.assetID == id || playback.captionsAssetID == id
        }.count
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
    case button
    case link
    case form
    case component

    var acceptsAuthoredChildren: Bool {
        switch self {
        case .frame, .section, .stack, .grid, .form: true
        case .text, .image, .button, .link, .component: false
        }
    }

    var isTextual: Bool { [.text, .button, .link].contains(self) }
    var isLinkControl: Bool { self == .button || self == .link }
}

/// SF-0409: one optional authored marker identifies the container whose
/// subtree is isolated. Focus, presentation and restoration remain editor
/// scene state and therefore never enter the package.
enum CanonicalIsolationRoot {
    static let key = "editor.isolation.v1.root"
    static let supportedKinds: Set<NodeKind> = [.frame, .section, .stack, .grid, .form]

    static func property(in node: DocumentNode) -> NodeProperty? {
        node.insertionProperty(key)
    }

    static func resolved(in document: CanonicalDocument) -> (pageID: PageID, nodeID: NodeID, property: NodeProperty)? {
        for page in document.pages {
            if let node = page.nodes.first(where: { property(in: $0) != nil }),
               let property = property(in: node) {
                return (page.id, node.id, property)
            }
        }
        return nil
    }

    static func validate(_ node: DocumentNode) throws {
        let owned = node.properties.filter { $0.key.rawValue == key }
        guard owned.count <= 1 else { throw ModelValidationError.invalidIsolationRootState }
        guard let property = owned.first else { return }
        guard supportedKinds.contains(node.kind), node.kind.acceptsAuthoredChildren,
              node.insertionGeometry != nil,
              case .boolean(true) = property.value else {
            throw ModelValidationError.invalidIsolationRootState
        }
    }
}

// MARK: - SF-0504 / SF-0510 / SF-0511 canonical style foundation

enum CanonicalPositionMode: String, Codable, CaseIterable, Hashable, Sendable {
    case `static`, relative, absolute, fixed, sticky
}

struct CanonicalPositioning: Equatable, Sendable {
    static let namespace = "layout.position.v1."
    static let supportedKinds: Set<NodeKind> = Set(NodeKind.allCases).subtracting([.component])
    let mode: CanonicalPositionMode
    let top: Double?
    let right: Double?
    let bottom: Double?
    let left: Double?
    let zIndex: Int
    let origin: PropertyOrigin

    static func resolve(_ node: DocumentNode) -> CanonicalPositioning? {
        guard supportedKinds.contains(node.kind), node.insertionGeometry != nil else { return nil }
        let modeProperty = node.insertionProperty(namespace + "mode")
        let mode = modeProperty.flatMap { property -> CanonicalPositionMode? in
            guard case .string(let raw) = property.value else { return nil }
            return CanonicalPositionMode(rawValue: raw)
        } ?? .static
        func number(_ suffix: String) -> Double? { node.insertionNumberProperty(namespace + suffix) }
        let rawZ = number("zIndex") ?? 0
        return .init(mode: mode, top: number("top"), right: number("right"),
                     bottom: number("bottom"), left: number("left"),
                     zIndex: Int(rawZ), origin: modeProperty?.origin ?? .defaulted)
    }

    static func validate(_ node: DocumentNode) throws {
        let properties = node.properties.filter { $0.key.rawValue.hasPrefix(namespace) }
        guard !properties.isEmpty else { return }
        guard supportedKinds.contains(node.kind), node.insertionGeometry != nil else {
            throw ModelValidationError.invalidPositioningState
        }
        let allowed = Set(["mode", "top", "right", "bottom", "left", "zIndex"].map { namespace + $0 })
        guard Set(properties.map { $0.key.rawValue }).isSubset(of: allowed) else {
            throw ModelValidationError.invalidPositioningState
        }
        for property in properties {
            switch property.key.rawValue {
            case namespace + "mode":
                guard case .string(let raw) = property.value, CanonicalPositionMode(rawValue: raw) != nil else {
                    throw ModelValidationError.invalidPositioningState
                }
            case namespace + "zIndex":
                guard case .number(let value) = property.value, value.isFinite,
                      value.rounded(.towardZero) == value, (-1_000_000...1_000_000).contains(value) else {
                    throw ModelValidationError.invalidPositioningState
                }
            default:
                guard case .number(let value) = property.value, value.isFinite,
                      (-1_000_000...1_000_000).contains(value) else {
                    throw ModelValidationError.invalidPositioningState
                }
            }
        }
        guard let resolved = resolve(node) else { throw ModelValidationError.invalidPositioningState }
        if resolved.mode == .static, [resolved.top, resolved.right, resolved.bottom, resolved.left].contains(where: { $0 != nil }) {
            throw ModelValidationError.invalidPositioningState
        }
    }
}

enum CanonicalInteractionStyleState: String, Codable, CaseIterable, Hashable, Sendable {
    case `default`, hover, focus, pressed, disabled
}

struct CanonicalReusableStyleDefinition: Equatable, Sendable {
    let id: ReusableStyleID
    let name: String
    let fill: CanonicalSolidColor?
    let opacity: Double?
    /// SF-0510 (document schema 23): linked border, corner radius and outer
    /// shadow. Empty for every style written before schema 23.
    let box: CanonicalReusableBoxAppearance

    init(id: ReusableStyleID, name: String, fill: CanonicalSolidColor?, opacity: Double?,
         box: CanonicalReusableBoxAppearance = .init()) {
        self.id = id; self.name = name; self.fill = fill; self.opacity = opacity; self.box = box
    }

    /// A definition must supply at least one appearance value.
    var hasAppearance: Bool { fill != nil || opacity != nil || !box.isEmpty }
}

/// SF-0510-001/003/004: the box appearance a reusable style links to its
/// objects. Each group (border, corner radius, outer shadow) is optional and
/// all-or-nothing; an omitted group supplies nothing, so the object's own
/// value or the default shows through. Colors are stored as canonical RGBA8
/// hexadecimal strings, exactly like linked fills. One field codec serves the
/// document, history and the clipboard so no path can drop a field.
struct CanonicalReusableBoxAppearance: Equatable, Sendable {
    /// The document schema that introduced linked box values.
    static let documentSchema = 23
    static let borderFields = ["borderWidth", "borderColor", "borderStyle"]
    static let cornerRadiusFields = ["cornerRadius"]
    static let shadowFields = ["shadowColor", "shadowOffsetX", "shadowOffsetY", "shadowBlur", "shadowSpread"]
    static let fields = Set(borderFields + cornerRadiusFields + shadowFields)

    var border: CanonicalBorder?
    var cornerRadius: Double?
    var shadow: CanonicalShadow?

    init(border: CanonicalBorder? = nil, cornerRadius: Double? = nil, shadow: CanonicalShadow? = nil) {
        self.border = border; self.cornerRadius = cornerRadius; self.shadow = shadow
    }

    var isEmpty: Bool { border == nil && cornerRadius == nil && shadow == nil }

    var isValid: Bool {
        (border?.isValid ?? true)
            && (cornerRadius.map { $0.isFinite && (0...10_000).contains($0) } ?? true)
            && (shadow?.isValid ?? true)
    }

    /// The value as stored: colors quantized to RGBA8. Registry comparisons use
    /// this so an off-grid source color is not reported as a pending change.
    var quantized: Self {
        func stored(_ color: CanonicalSolidColor) -> CanonicalSolidColor {
            CanonicalSolidColor.parse(hexadecimal: color.hexadecimalRGBA) ?? color
        }
        return Self(
            border: border.map { CanonicalBorder(color: stored($0.color), width: $0.width, style: $0.style) },
            cornerRadius: cornerRadius,
            shadow: shadow.map {
                CanonicalShadow(color: stored($0.color), offsetX: $0.offsetX, offsetY: $0.offsetY,
                                blur: $0.blur, spread: $0.spread)
            }
        )
    }

    /// Field name and value pairs in a fixed order (definition key suffixes).
    var fieldValues: [(field: String, value: PropertyValue)] {
        var values: [(field: String, value: PropertyValue)] = []
        if let border {
            values.append((field: "borderWidth", value: .number(border.width)))
            values.append((field: "borderColor", value: .string(border.color.hexadecimalRGBA)))
            values.append((field: "borderStyle", value: .string(border.style.rawValue)))
        }
        if let cornerRadius { values.append((field: "cornerRadius", value: .number(cornerRadius))) }
        if let shadow {
            values.append((field: "shadowColor", value: .string(shadow.color.hexadecimalRGBA)))
            values.append((field: "shadowOffsetX", value: .number(shadow.offsetX)))
            values.append((field: "shadowOffsetY", value: .number(shadow.offsetY)))
            values.append((field: "shadowBlur", value: .number(shadow.blur)))
            values.append((field: "shadowSpread", value: .number(shadow.spread)))
        }
        return values
    }

    /// Deterministic text form for equivalence checks (clipboard reuse).
    var semanticFingerprint: String {
        fieldValues.map { entry -> String in
            let text: String
            switch entry.value {
            case .string(let value): text = value
            case .number(let value): text = String(format: "%.17g", locale: Locale(identifier: "en_US_POSIX"), value)
            case .boolean(let value): text = value ? "true" : "false"
            }
            return entry.field + "=" + text
        }.joined(separator: ";")
    }

    /// Strict decode of a definition's box fields (suffix -> value). A partial
    /// group, non-canonical color spelling, wrong type, out-of-range value or
    /// unknown field is invalid rather than silently dropped.
    static func decode(_ values: [String: PropertyValue]) throws -> Self {
        let invalid = ModelValidationError.invalidReusableStyleState
        guard Set(values.keys).isSubset(of: fields) else { throw invalid }
        func number(_ field: String) throws -> Double {
            guard case .number(let value)? = values[field], value.isFinite else { throw invalid }
            return value
        }
        func color(_ field: String) throws -> CanonicalSolidColor {
            guard case .string(let raw)? = values[field],
                  let value = CanonicalSolidColor.parse(hexadecimal: raw),
                  value.hexadecimalRGBA == raw else { throw invalid }
            return value
        }
        func present(_ group: [String]) throws -> Bool {
            let count = group.filter { values[$0] != nil }.count
            guard count == 0 || count == group.count else { throw invalid }
            return count == group.count
        }
        var result = Self()
        let hasBorder = try present(borderFields)
        let hasCornerRadius = try present(cornerRadiusFields)
        let hasShadow = try present(shadowFields)
        if hasBorder {
            guard case .string(let raw)? = values["borderStyle"],
                  let style = CanonicalBorderStyle(rawValue: raw) else { throw invalid }
            result.border = CanonicalBorder(color: try color("borderColor"), width: try number("borderWidth"), style: style)
        }
        if hasCornerRadius { result.cornerRadius = try number("cornerRadius") }
        if hasShadow {
            result.shadow = CanonicalShadow(color: try color("shadowColor"), offsetX: try number("shadowOffsetX"),
                offsetY: try number("shadowOffsetY"), blur: try number("shadowBlur"), spread: try number("shadowSpread"))
        }
        guard result.isValid else { throw invalid }
        return result
    }

    /// True for a reusable-style definition property that schema 23 introduced.
    static func ownsDefinitionProperty(_ property: NodeProperty) -> Bool {
        let key = property.key.rawValue
        let prefix = CanonicalReusableStyleIndex.namespace + "definition."
        guard key.hasPrefix(prefix), let field = key.split(separator: ".").last else { return false }
        return fields.contains(String(field))
    }
}

struct CanonicalReusableStyleIndex: Sendable {
    static let namespace = "style.reusable.v1."
    static let appliedKey = namespace + "applied"
    static let stateNamespace = "style.state.v1."
    static let definitionFields = Set(["name", "fill", "opacity"]).union(CanonicalReusableBoxAppearance.fields)
    let orderedDefinitions: [CanonicalReusableStyleDefinition]
    let byID: [ReusableStyleID: CanonicalReusableStyleDefinition]

    init(document: CanonicalDocument) throws {
        var definitions: [CanonicalReusableStyleDefinition] = []
        let definitionPrefix = Self.namespace + "definition."
        for node in document.pages.flatMap(\.nodes) {
            // SF-0510-007: one pass groups this node's definition properties by
            // their style-ID segment, in stored order, so building the index is
            // linear in the node's properties instead of a rescan per style.
            var grouped: [Substring: [NodeProperty]] = [:]
            var names: [NodeProperty] = []
            for property in node.properties where property.key.rawValue.hasPrefix(definitionPrefix) {
                let parts = property.key.rawValue.split(separator: ".")
                if parts.count == 6 { grouped[parts[4], default: []].append(property) }
                if property.key.rawValue.hasSuffix(".name") { names.append(property) }
            }
            for nameProperty in names {
                let parts = nameProperty.key.rawValue.split(separator: ".")
                guard parts.count == 6, let id = ReusableStyleID(uuidString: String(parts[4])),
                      case .string(let name) = nameProperty.value,
                      Self.validName(name) else { throw ModelValidationError.invalidReusableStyleState }
                let prefix = definitionPrefix + "\(id.description)."
                let owned = grouped[parts[4]] ?? []
                // Same lookup as `insertionProperty`: the first property with the exact key.
                func stored(_ field: String) -> NodeProperty? { owned.first { $0.key.rawValue == prefix + field } }
                let fillProperty = stored("fill")
                let fill: CanonicalSolidColor? = {
                    guard case .string(let raw)? = fillProperty?.value else { return nil }
                    return CanonicalSolidColor.parse(hexadecimal: raw)
                }()
                let opacity: Double? = {
                    guard case .number(let value)? = stored("opacity")?.value else { return nil }
                    return value
                }()
                var boxValues: [String: PropertyValue] = [:]
                for property in owned where property.key.rawValue.hasPrefix(prefix) {
                    let field = String(property.key.rawValue.dropFirst(prefix.count))
                    guard CanonicalReusableBoxAppearance.fields.contains(field) else { continue }
                    // A repeated field would make the stored value ambiguous.
                    guard boxValues.updateValue(property.value, forKey: field) == nil else {
                        throw ModelValidationError.invalidReusableStyleState
                    }
                }
                let box = try CanonicalReusableBoxAppearance.decode(boxValues)
                let definition = CanonicalReusableStyleDefinition(id: id, name: name, fill: fill, opacity: opacity, box: box)
                guard fillProperty == nil || fill != nil,
                      opacity.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
                      definition.hasAppearance else {
                    throw ModelValidationError.invalidReusableStyleState
                }
                definitions.append(definition)
            }
        }
        guard Set(definitions.map(\.id)).count == definitions.count,
              definitions.count <= 1_000,
              Set(definitions.map { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "en_US_POSIX")) }).count == definitions.count else {
            throw ModelValidationError.invalidReusableStyleState
        }
        orderedDefinitions = definitions
        byID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        for node in document.pages.flatMap(\.nodes) {
            let definitionProperties = node.properties.filter {
                $0.key.rawValue.hasPrefix(Self.namespace + "definition.")
            }
            for property in definitionProperties {
                let parts = property.key.rawValue.split(separator: ".")
                guard parts.count == 6, let id = ReusableStyleID(uuidString: String(parts[4])),
                      byID[id] != nil,
                      Self.definitionFields.contains(String(parts[5])) else {
                    throw ModelValidationError.invalidReusableStyleState
                }
            }
            for id in try Self.strictlyDecodedAppliedIDs(node) where byID[id] == nil {
                throw ModelValidationError.invalidReusableStyleState
            }
            try Self.validateStateProperties(node)
        }
    }

    static func appliedIDs(_ node: DocumentNode) -> [ReusableStyleID] {
        guard let raw = node.insertionStringProperty(appliedKey), !raw.isEmpty else { return [] }
        return raw.split(separator: ",").compactMap { ReusableStyleID(uuidString: String($0)) }
    }

    static func strictlyDecodedAppliedIDs(_ node: DocumentNode) throws -> [ReusableStyleID] {
        guard let raw = node.insertionStringProperty(appliedKey) else { return [] }
        if raw.isEmpty { return [] }
        let tokens = raw.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard tokens.allSatisfy({ !$0.isEmpty }), tokens.count <= 32 else {
            throw ModelValidationError.invalidReusableStyleState
        }
        let ids = try tokens.map { token -> ReusableStyleID in
            guard let id = ReusableStyleID(uuidString: token), id.description == token else {
                throw ModelValidationError.invalidReusableStyleState
            }
            return id
        }
        guard Set(ids).count == ids.count else { throw ModelValidationError.invalidReusableStyleState }
        return ids
    }

    static func validName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value == trimmed && !value.isEmpty && value.utf8.count <= 128
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    static func validateStateProperties(_ node: DocumentNode) throws {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix(stateNamespace) }
        var fieldsByState: [CanonicalInteractionStyleState: Set<String>] = [:]
        var variantIDs = Set<UUID>()
        for property in owned {
            let parts = property.key.rawValue.split(separator: ".")
            guard parts.count == 5, let state = CanonicalInteractionStyleState(rawValue: String(parts[3])),
                  state != .default else { throw ModelValidationError.invalidInteractionStyleState }
            fieldsByState[state, default: []].insert(String(parts[4]))
            switch parts[4] {
            case "fill": guard case .string(let raw) = property.value, CanonicalSolidColor.parse(hexadecimal: raw) != nil else { throw ModelValidationError.invalidInteractionStyleState }
            case "opacity": guard case .number(let value) = property.value, value.isFinite, (0...1).contains(value) else { throw ModelValidationError.invalidInteractionStyleState }
            case "id":
                guard case .string(let raw) = property.value, let id = UUID(uuidString: raw),
                      raw.lowercased() == id.uuidString.lowercased(), variantIDs.insert(id).inserted else {
                    throw ModelValidationError.invalidInteractionStyleState
                }
            default: throw ModelValidationError.invalidInteractionStyleState
            }
        }
        guard fieldsByState.values.allSatisfy({ $0.contains("id") && ($0.contains("fill") || $0.contains("opacity")) }) else {
            throw ModelValidationError.invalidInteractionStyleState
        }
    }
}

struct CanonicalResolvedAppearance: Equatable, Sendable {
    let fill: CanonicalSolidColor?
    let opacity: Double
    let appliedStyleIDs: [ReusableStyleID]
    let state: CanonicalInteractionStyleState

    static func resolve(
        node: DocumentNode,
        index: CanonicalReusableStyleIndex,
        state: CanonicalInteractionStyleState = .default
    ) throws -> CanonicalResolvedAppearance {
        let applied = try CanonicalReusableStyleIndex.strictlyDecodedAppliedIDs(node)
        var fill: CanonicalSolidColor?
        var opacity = 1.0
        for id in applied {
            guard let definition = index.byID[id] else { throw ModelValidationError.invalidReusableStyleState }
            if let value = definition.fill { fill = value }
            if let value = definition.opacity { opacity = value }
        }
        if let layers = CanonicalFillLayerCodec.layers(for: node) {
            // An explicit empty fill stack means None, not permission to
            // resurrect an inherited solid behind a gradient/transparent page.
            fill = layers.last(where: { $0.isEnabled && $0.kind == .solid })?.solidColor
        } else if let local = CanonicalFillLayerCodec.legacySolidLayer(for: node)?.solidColor {
            fill = local
        }
        if let localOpacity = node.insertionNumberProperty("style.opacity") { opacity = localOpacity }
        if state != .default {
            let prefix = CanonicalReusableStyleIndex.stateNamespace + state.rawValue + "."
            if let value = node.insertionStringProperty(prefix + "fill").flatMap({ CanonicalSolidColor.parse(hexadecimal: $0) }) {
                fill = value
            }
            if let value = node.insertionNumberProperty(prefix + "opacity") { opacity = value }
        }
        return .init(fill: fill, opacity: opacity, appliedStyleIDs: applied, state: state)
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

// SF-1203-001...008 — semantic output stays typed canonical document state.
// Absence means the deterministic node-kind default; an authored property
// records only a deliberate author choice. No markup string is stored here.
enum SemanticHTMLElement: String, CaseIterable, Sendable {
    case div, section, main, header, footer, nav, article, aside
    case p, h1, h2, h3, h4, h5, h6
    case img, button, a, form
}

enum CanonicalSemanticElement {
    static let key = "semantic.html.v1.element"

    static func defaultElement(for kind: NodeKind) -> SemanticHTMLElement? {
        switch kind {
        case .frame, .stack, .grid: .div
        case .section: .section
        case .text: .p
        case .image: .img
        case .button: .button
        case .link: .a
        case .form: .form
        case .component: nil
        }
    }

    static func supportedElements(for kind: NodeKind) -> [SemanticHTMLElement] {
        switch kind {
        case .frame, .stack, .grid: [.div, .section, .main, .header, .footer, .nav, .article, .aside]
        case .section: [.section, .main, .header, .footer, .nav, .article, .aside, .div]
        case .text: [.p, .h1, .h2, .h3, .h4, .h5, .h6]
        case .image: [.img]
        case .button: [.button]
        case .link: [.a]
        case .form: [.form]
        case .component: []
        }
    }

    /// The sole typed semantic resolver shared by Inspector, static planning,
    /// and any immutable output snapshot. Invalid historical metadata has no
    /// output effect; absence remains the deterministic kind default.
    static func resolved(for node: DocumentNode) -> (SemanticHTMLElement, PropertyOrigin)? {
        guard let fallback = defaultElement(for: node.kind) else { return nil }
        guard let property = node.insertionProperty(key) else { return (fallback, .defaulted) }
        guard case .string(let raw) = property.value,
              let element = SemanticHTMLElement(rawValue: raw),
              supportedElements(for: node.kind).contains(element) else {
            return nil
        }
        return (element, property.origin)
    }
}

// SF-AUTHORING-098, SF-0701/SF-0702/SF-1203 — authored accessibility
// metadata is deliberately small and semantic. Roles continue to come from
// the typed HTML element; Image alt text and Form-field labels retain their
// established dedicated schemas rather than competing with these properties.
enum CanonicalAccessibilityMetadata {
    enum Field: String, CaseIterable, Sendable {
        case name, help
        var key: String { "accessibility.v1." + rawValue }
        var title: String { self == .name ? "Accessible name" : "Description" }
        var maximumLength: Int { self == .name ? 256 : 512 }
    }

    static let supportedKinds: Set<NodeKind> = [.frame, .text, .section, .stack, .grid, .button, .link]

    static func value(_ field: Field, for node: DocumentNode) -> (String?, PropertyOrigin) {
        guard let property = node.insertionProperty(field.key),
              case .string(let value) = property.value else { return (nil, .defaulted) }
        return (value, property.origin)
    }

    static func validate(_ node: DocumentNode) throws {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix("accessibility.v1.") }
        guard !owned.isEmpty else { return }
        guard supportedKinds.contains(node.kind), owned.count <= Field.allCases.count else {
            throw ModelValidationError.invalidAccessibilityMetadataState
        }
        for property in owned {
            guard property.origin == .authored,
                  let field = Field.allCases.first(where: { $0.key == property.key.rawValue }),
                  case .string(let value) = property.value,
                  value == value.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty, value.count <= field.maximumLength,
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw ModelValidationError.invalidAccessibilityMetadataState
            }
        }
    }
}

// SF-1204 v1 stores typed rule intent, never raw CSS text. The renderer and
// preview derive a collision-free selector solely from the stable NodeID.
enum CanonicalCSSRule {
    static let key = "css.rule.v1"
    static let defaultValue = "node"
    static func selector(for nodeID: NodeID) -> String {
        "[data-siteforge-node=\"\(nodeID.rawValue.uuidString.lowercased())\"]"
    }
}

// SF-1006 v1 text-field intent is canonical metadata; submitted values never
// enter project state. The three properties retain omitted/defaulted/authored
// provenance independently through the existing property model.
enum CanonicalFormField {
    static let labelKey = "form.field.v1.label"
    static let nameKey = "form.field.v1.name"
    static let requiredKey = "form.field.v1.required"
    static let helpKey = "form.field.v1.help"
    static let kindKey = "form.field.v1.kind"
    static let optionsKey = "form.field.v1.options"
    /// Optional authored input bound. Omission deliberately retains the
    /// documented local-validation default rather than serializing a copy.
    static let maximumLengthKey = "form.field.v1.maximumLength"
    static let minimumMaximumLength = 1
    static let maximumMaximumLength = 4_096
}

/// Ordered select options are canonical typed data encoded through the
/// scalar property envelope. Their stable identity is retained across edits,
/// duplication, history, recovery, and package round trips.
struct CanonicalFormSelectOption: Codable, Equatable, Identifiable, Sendable {
    let id: FormOptionID
    let label: String
    let value: String

    init(id: FormOptionID = FormOptionID(), label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }
}

enum CanonicalFormSelectOptions {
    static let maximumOptions = 100
    static let maximumTextLength = 256

    static func encode(_ options: [CanonicalFormSelectOption]) throws -> String {
        try validate(options)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(options), as: UTF8.self)
    }

    static func decode(_ value: String) throws -> [CanonicalFormSelectOption] {
        let options = try JSONDecoder().decode([CanonicalFormSelectOption].self, from: Data(value.utf8))
        try validate(options)
        return options
    }

    /// Page duplication owns all nested canonical identity remapping. Option
    /// labels and submitted values are intentional content; only option IDs
    /// are regenerated so a later reorder/delete cannot alias the source page.
    static func remappingStableIDs(in value: String) throws -> String {
        try encode(try decode(value).map { option in
            .init(label: option.label, value: option.value)
        })
    }

    static func validate(_ options: [CanonicalFormSelectOption]) throws {
        guard !options.isEmpty, options.count <= maximumOptions,
              Set(options.map(\.id)).count == options.count,
              Set(options.map(\.value)).count == options.count,
              options.allSatisfy({ option in
                  !option.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  !option.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  option.label.count <= maximumTextLength && option.value.count <= maximumTextLength &&
                  !option.label.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) &&
                  !option.value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
              }) else {
            throw ModelValidationError.invalidSemanticElementState
        }
    }
}

enum FluidValueIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "fluid-value"
}
typealias FluidValueID = StableIdentifier<FluidValueIdentifierDomain>

enum FluidValueCurve: String, Codable, CaseIterable, Sendable { case linear }

/// SF-0604 v1 canonical clamp. The value's identity remains stable across
/// edits/history while its owning property supplies provenance and ordering.
struct CanonicalFluidValue: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let lowerViewport = 390.0
    static let preferredViewport = 768.0
    static let upperViewport = 1_440.0
    let schemaVersion: Int
    let id: FluidValueID
    let minimum: Double
    let preferred: Double
    let maximum: Double
    let curve: FluidValueCurve

    init(id: FluidValueID = FluidValueID(), minimum: Double, preferred: Double,
         maximum: Double, curve: FluidValueCurve = .linear) {
        self.schemaVersion = Self.schemaVersion; self.id = id
        self.minimum = minimum; self.preferred = preferred; self.maximum = maximum; self.curve = curve
    }
    var isValid: Bool {
        schemaVersion == Self.schemaVersion
            && [minimum, preferred, maximum].allSatisfy { $0.isFinite && abs($0) <= 1_000_000_000 }
            && minimum <= preferred && preferred <= maximum
    }
    func resolved(viewportWidth: Double) -> Double? {
        guard isValid, viewportWidth.isFinite else { return nil }
        if viewportWidth <= Self.lowerViewport { return minimum }
        if viewportWidth >= Self.upperViewport { return maximum }
        let lower: Double, upper: Double, start: Double, end: Double
        if viewportWidth <= Self.preferredViewport {
            lower = Self.lowerViewport; upper = Self.preferredViewport; start = minimum; end = preferred
        } else {
            lower = Self.preferredViewport; upper = Self.upperViewport; start = preferred; end = maximum
        }
        return start + ((viewportWidth - lower) / (upper - lower)) * (end - start)
    }
}

enum FluidValueTarget: String, Codable, CaseIterable, Hashable, Sendable {
    case width, height, fontSize, lineHeight, padding, gap
    var title: String {
        switch self {
        case .width: "Width"; case .height: "Height"; case .fontSize: "Font Size"
        case .lineHeight: "Line Height"; case .padding: AuthoringLanguage.innerSpacing; case .gap: AuthoringLanguage.itemSpacing
        }
    }
    var fixedPropertyKey: String {
        switch self {
        case .width: "layout.width"; case .height: "layout.height"
        case .fontSize: CanonicalTypography.namespace + "size"
        case .lineHeight: CanonicalTypography.namespace + "lineHeight"
        case .padding: "layout.padding"; case .gap: "layout.gap"
        }
    }
    func supports(_ kind: NodeKind) -> Bool {
        switch self {
        case .width, .height: [.frame, .text, .section, .stack, .grid, .image, .button, .link].contains(kind)
        case .fontSize, .lineHeight: kind.isTextual
        case .padding: [.section, .stack, .grid].contains(kind)
        case .gap: [.stack, .grid].contains(kind)
        }
    }
    func accepts(_ value: Double) -> Bool {
        guard value.isFinite else { return false }
        return switch self {
        case .width, .height: (1...1_000_000_000).contains(value)
        case .fontSize: (1...1_000).contains(value)
        case .lineHeight: (1...2_000).contains(value)
        case .padding, .gap: (0...10_000).contains(value)
        }
    }
}

enum CanonicalFluidValueCodec {
    static let namespace = "responsive.fluid.v1"
    static func key(_ target: FluidValueTarget) -> String { "\(namespace).\(target.rawValue)" }
    static func encode(_ value: CanonicalFluidValue, target: FluidValueTarget) throws -> String {
        guard value.isValid, target.accepts(value.minimum), target.accepts(value.preferred),
              target.accepts(value.maximum) else { throw ModelValidationError.invalidFluidValueState }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
    static func decode(_ raw: String, target: FluidValueTarget) throws -> CanonicalFluidValue {
        let data = Data(raw.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["schemaVersion", "id", "minimum", "preferred", "maximum", "curve"]
        else { throw ModelValidationError.invalidFluidValueState }
        let value = try JSONDecoder().decode(CanonicalFluidValue.self, from: data)
        guard value.isValid, target.accepts(value.minimum), target.accepts(value.preferred),
              target.accepts(value.maximum) else { throw ModelValidationError.invalidFluidValueState }
        return value
    }
    static func remappingStableID(in raw: String, target: FluidValueTarget) throws -> String {
        let value = try decode(raw, target: target)
        return try encode(.init(minimum: value.minimum, preferred: value.preferred,
                                maximum: value.maximum, curve: value.curve), target: target)
    }
    static func value(for target: FluidValueTarget, node: DocumentNode) -> (CanonicalFluidValue, PropertyOrigin)? {
        guard target.supports(node.kind), let property = node.insertionProperty(key(target)),
              case .string(let raw) = property.value,
              let value = try? decode(raw, target: target) else { return nil }
        return (value, property.origin)
    }
    static func resolved(_ target: FluidValueTarget, node: DocumentNode, viewportWidth: Double) -> Double? {
        value(for: target, node: node)?.0.resolved(viewportWidth: viewportWidth)
    }
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

    /// The one headless resolution path for canonical text style. Callers
    /// retain the property-origin separately; this value only supplies the
    /// deterministic effective style without resolving installed fonts.
    static func resolved(for node: DocumentNode) -> CanonicalTypography? {
        guard node.kind.isTextual else { return nil }
        func string(_ suffix: String) -> String? { node.insertionStringProperty(namespace + suffix) }
        func number(_ suffix: String) -> Double? { node.insertionNumberProperty(namespace + suffix) }
        let fallback = defaultValue
        let value = CanonicalTypography(
            family: string("family") ?? fallback.family,
            weight: string("weight").flatMap(CanonicalFontWeight.init(rawValue:)) ?? fallback.weight,
            size: number("size") ?? fallback.size,
            lineHeight: number("lineHeight") ?? fallback.lineHeight,
            tracking: number("tracking") ?? fallback.tracking,
            alignment: string("alignment").flatMap(CanonicalTextAlignment.init(rawValue:))
                ?? (node.kind == .button ? .center : fallback.alignment)
        )
        return value.isValid ? value : nil
    }
}

/// Optional whole-object foreground. Four normalized channels form one
/// canonical value; absence keeps the existing automatic contrast policy.
enum CanonicalTextForeground {
    static let prefix = "style.typography.v1.foreground."
    static let channels = ["red", "green", "blue", "alpha"]

    static func literal(for node: DocumentNode) -> CanonicalSolidColor? {
        let numbers = channels.compactMap { node.insertionNumberProperty(prefix + $0) }
        guard numbers.count == 4 else { return nil }
        let color = CanonicalSolidColor(red: numbers[0], green: numbers[1], blue: numbers[2], alpha: numbers[3])
        return color.isValid ? color : nil
    }

    static func values(_ color: CanonicalSolidColor) -> [(String, PropertyValue)] {
        zip(channels, [color.red, color.green, color.blue, color.alpha])
            .map { (prefix + $0.0, .number($0.1)) }
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
    /// A reusable node graph, never a website route.
    case componentDefinition
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

// SF-0806-001, SF-1102-001: editor loading never follows these references.
// Page/section identities survive naming and route changes; missing targets
// stay representable so the Inspector can offer repair or removal.
enum CanonicalLinkContext: String, CaseIterable, Codable, Hashable, Sendable {
    case same, new
}

extension DocumentNode {
    var controlLabel: String { insertionStringProperty(CanonicalLinkTarget.labelKey) ?? kind.rawValue.capitalized }
    var controlContext: CanonicalLinkContext {
        insertionStringProperty(CanonicalLinkTarget.namespace + "context").flatMap(CanonicalLinkContext.init(rawValue:)) ?? .same
    }
}

enum CanonicalLinkTarget: Codable, Hashable, Sendable {
    case none
    case page(PageID)
    case section(pageID: PageID, nodeID: NodeID)
    case external(String)

    static let namespace = "interaction.link.v1."
    static let labelKey = "content.control.v1.label"

    static func validate(_ node: DocumentNode) throws {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix("interaction.link.") || $0.key.rawValue.hasPrefix("content.control.") }
        guard node.kind.isLinkControl else {
            guard owned.isEmpty else { throw CanonicalLinkError.invalidTarget }
            return
        }
        let allowed = Set(["kind", "pageID", "nodeID", "url", "context"].map { namespace + $0 } + [labelKey])
        guard owned.allSatisfy({ allowed.contains($0.key.rawValue) }) else { throw CanonicalLinkError.invalidTarget }
        if let property = node.insertionProperty(labelKey) {
            guard case .string(let label) = property.value, label.utf8.count <= 4096,
                  label.rangeOfCharacter(from: .controlCharacters) == nil else { throw CanonicalLinkError.invalidLabel }
        }
        if let context = node.insertionProperty(namespace + "context") {
            guard case .string(let value) = context.value, CanonicalLinkContext(rawValue: value) != nil
            else { throw CanonicalLinkError.invalidTarget }
        }
        _ = try resolve(node)
    }

    var properties: [(String, PropertyValue)] {
        switch self {
        case .none: [(Self.namespace + "kind", .string("none"))]
        case .page(let id): [
            (Self.namespace + "kind", .string("page")),
            (Self.namespace + "pageID", .string(id.description))]
        case .section(let pageID, let nodeID): [
            (Self.namespace + "kind", .string("section")),
            (Self.namespace + "pageID", .string(pageID.description)),
            (Self.namespace + "nodeID", .string(nodeID.description))]
        case .external(let url): [
            (Self.namespace + "kind", .string("external")),
            (Self.namespace + "url", .string(url))]
        }
    }

    static func validateExternal(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 8192,
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0)
                  || CharacterSet.controlCharacters.contains($0) }),
              !value.contains("\\"),
              let components = URLComponents(string: value),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.url != nil else { return false }
        if let port = components.port, !(1...65535).contains(port) { return false }
        return true
    }

    static func resolve(_ node: DocumentNode) throws -> CanonicalLinkTarget {
        let targetKeys = ["kind", "pageID", "nodeID", "url"].map { namespace + $0 }
        let present = Set(node.properties.filter { targetKeys.contains($0.key.rawValue) }.map { $0.key.rawValue })
        if present.isEmpty { return .none }
        func exact(_ suffixes: [String]) -> Bool { present == Set(suffixes.map { namespace + $0 }) }
        switch node.insertionStringProperty(namespace + "kind") {
        case "none" where exact(["kind"]): return .none
        case "page" where exact(["kind", "pageID"]):
            guard let value = node.insertionStringProperty(namespace + "pageID"),
                  let id = PageID(uuidString: value) else { throw CanonicalLinkError.invalidTarget }
            return .page(id)
        case "section" where exact(["kind", "pageID", "nodeID"]):
            guard let page = node.insertionStringProperty(namespace + "pageID"), let pageID = PageID(uuidString: page),
                  let node = node.insertionStringProperty(namespace + "nodeID"), let nodeID = NodeID(uuidString: node)
            else { throw CanonicalLinkError.invalidTarget }
            return .section(pageID: pageID, nodeID: nodeID)
        case "external" where exact(["kind", "url"]):
            guard let value = node.insertionStringProperty(namespace + "url"), validateExternal(value)
            else { throw CanonicalLinkError.invalidTarget }
            return .external(value)
        default: throw CanonicalLinkError.invalidTarget
        }
    }

    func isMissing(in document: CanonicalDocument) -> Bool {
        switch self {
        case .none, .external: false
        case .page(let id): !document.pages.contains { $0.id == id }
        case .section(let pageID, let nodeID):
            !document.pages.contains { $0.id == pageID && $0.nodes.contains { $0.id == nodeID && $0.kind == .section } }
        }
    }
}

enum CanonicalLinkError: Error, Equatable, LocalizedError, Sendable {
    case invalidTarget, invalidLabel
    var errorDescription: String? {
        switch self {
        case .invalidTarget: "Choose a page or section, or enter a complete HTTP or HTTPS URL without credentials."
        case .invalidLabel: "Enter a label of at most 4,096 UTF-8 bytes without control characters."
        }
    }
}

/// SF-0802-001/004/005: optional QR intent is bound to immutable image bytes.
struct CanonicalQRCode: Equatable, Sendable {
    static let namespace = "content.qr.v1."
    let payload: String
    let hash: String
    static func resolve(_ node: DocumentNode) throws -> Self? {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix("content.qr.") }
        guard !owned.isEmpty else { return nil }
        guard node.kind == .image, owned.count == 2,
              Set(owned.map(\.key.rawValue)) == [namespace + "payload", namespace + "hash"],
              let payload = node.insertionStringProperty(namespace + "payload"), payload.utf8.count <= 1_024,
              CanonicalLinkTarget.validateExternal(payload),
              let hash = node.insertionStringProperty(namespace + "hash"),
              hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              CanonicalImageStyle.resolve(node) != nil else { throw ModelValidationError.invalidImageReference }
        return .init(payload: payload, hash: hash)
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

/// One optional local raster background for Frame/Section. An unresolved
/// stable reference remains authored intent; resource availability is a
/// separate package/runtime concern, never a reason to rewrite the node.
struct CanonicalImageFill: Equatable, Sendable {
    static let namespace = "style.fill.image.v1."
    static let assetKey = namespace + "assetID"
    static let modeKey = namespace + "mode"
    let assetID: AssetID
    let mode: ImageFitMode

    static func resolve(_ node: DocumentNode) -> CanonicalImageFill? {
        guard [.frame, .section].contains(node.kind),
              let raw = node.insertionStringProperty(assetKey),
              let id = AssetID(uuidString: raw) else { return nil }
        let mode = node.insertionStringProperty(modeKey).flatMap(ImageFitMode.init(rawValue:)) ?? .fill
        return .init(assetID: id, mode: mode)
    }

    static func validate(_ node: DocumentNode) throws {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix(namespace) }
        guard !owned.isEmpty else { return }
        guard [.frame, .section].contains(node.kind),
              Set(owned.map(\.key.rawValue)).isSubset(of: [assetKey, modeKey]),
              resolve(node) != nil else { throw ModelValidationError.invalidImageReference }
        if let mode = node.insertionProperty(modeKey) {
            guard case .string(let raw) = mode.value, [.fit, .fill].contains(ImageFitMode(rawValue: raw)) else {
                throw ModelValidationError.invalidImageReference
            }
        }
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

    static func deterministicUUID(namespace: UUID, label: String) -> UUID {
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

/// SF-1107 (OD-041, ADR-0037): HTML and CSS the author writes for the
/// published site. SiteForge writes it exactly as entered, never validates it
/// as HTML and never runs it in the editor. A field is either absent or
/// non-blank text of at most 64 KiB without NUL. It may not close the element
/// it is placed in, so it cannot end the generated head, body or style early.
struct CustomCodeBlock: Codable, Equatable, Sendable {
    static let maximumBytes = 65_536
    static let invalidExplanation = "Custom code fields hold at most 64 KB each and cannot contain </head>, <body>, </body>, </html> or </style> where they would end SiteForge's own markup."
    var headHTML: String?
    var bodyHTML: String?
    var css: String?

    init(headHTML: String? = nil, bodyHTML: String? = nil, css: String? = nil) {
        self.headHTML = headHTML; self.bodyHTML = bodyHTML; self.css = css
    }

    /// Nil when every field is blank, so "no custom code" has one representation.
    static func make(headHTML: String, bodyHTML: String, css: String) -> Self? {
        func field(_ text: String) -> String? {
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        }
        let block = Self(headHTML: field(headHTML), bodyHTML: field(bodyHTML), css: field(css))
        return block.isEmpty ? nil : block
    }

    var isEmpty: Bool { headHTML == nil && bodyHTML == nil && css == nil }

    var isValid: Bool {
        !isEmpty
            && Self.validField(headHTML, forbidden: ["</head", "<body", "</body", "</html"])
            && Self.validField(bodyHTML, forbidden: ["</body", "</html"])
            && Self.validField(css, forbidden: ["</style"])
    }

    static func validField(_ value: String?, forbidden: [String]) -> Bool {
        guard let value else { return true }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.utf8.count <= maximumBytes, !value.contains("\u{0}") else { return false }
        let lowered = value.lowercased()
        return !forbidden.contains { lowered.contains($0) }
    }

    /// True when the HTML can run script in a visitor's browser.
    var containsScript: Bool {
        [headHTML, bodyHTML].compactMap { $0?.lowercased() }.contains { html in
            html.contains("<script") || html.contains("javascript:")
                || html.range(of: #"\son[a-z]+\s*="#, options: .regularExpression) != nil
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case headHTML, bodyHTML, css }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        headHTML = try values.decodeIfPresent(String.self, forKey: .headHTML)
        bodyHTML = try values.decodeIfPresent(String.self, forKey: .bodyHTML)
        css = try values.decodeIfPresent(String.self, forKey: .css)
        guard isValid else { throw ModelValidationError.invalidWebsiteMetadata }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(headHTML, forKey: .headHTML)
        try values.encode(bodyHTML, forKey: .bodyHTML)
        try values.encode(css, forKey: .css)
    }
}

/// SF-1207: optional fields are omitted intent, never equivalent authored
/// literals. Effective defaults/provenance are resolved without rewriting them.
struct PageWebsiteMetadata: Codable, Equatable, Sendable {
    let pageID: PageID
    var title: String?
    var description: String?
    var allowsIndexing: Bool?
    /// SF-1107: this page's custom code (website metadata version 3). The key is
    /// written only when set.
    var customCode: CustomCodeBlock?

    init(pageID: PageID, title: String? = nil, description: String? = nil, allowsIndexing: Bool? = nil,
         customCode: CustomCodeBlock? = nil) {
        self.pageID = pageID; self.title = title; self.description = description; self.allowsIndexing = allowsIndexing
        self.customCode = customCode
    }
    var isEmpty: Bool { title == nil && description == nil && allowsIndexing == nil && customCode == nil }
    var isValid: Bool {
        WebsiteMetadata.validText(title, maximumBytes: 512)
            && WebsiteMetadata.validText(description, maximumBytes: 2_048)
            && (customCode?.isValid ?? true)
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case pageID, title, description, allowsIndexing, customCode }
    private enum BaseCodingKeys: String, CodingKey, CaseIterable { case pageID, title, description, allowsIndexing }
    init(from decoder: Decoder) throws {
        let actual = Set(try decoder.container(keyedBy: AnySiteForgeCodingKey.self).allKeys.map(\.stringValue))
        let base = Set(BaseCodingKeys.allCases.map(\.stringValue))
        guard actual == base || actual == base.union([CodingKeys.customCode.stringValue]) else {
            throw ModelValidationError.invalidWebsiteMetadata
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pageID = try values.decode(PageID.self, forKey: .pageID)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        allowsIndexing = try values.decodeIfPresent(Bool.self, forKey: .allowsIndexing)
        if values.contains(.customCode), try values.decodeNil(forKey: .customCode) {
            throw ModelValidationError.invalidWebsiteMetadata
        }
        customCode = try values.decodeIfPresent(CustomCodeBlock.self, forKey: .customCode)
        guard isValid else { throw ModelValidationError.invalidWebsiteMetadata }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(pageID, forKey: .pageID)
        try values.encode(title, forKey: .title)
        try values.encode(description, forKey: .description)
        try values.encode(allowsIndexing, forKey: .allowsIndexing)
        try values.encodeIfPresent(customCode, forKey: .customCode)
    }
}

struct WebsiteMetadata: Codable, Equatable, Sendable {
    /// Version 2 (SF-1207, ADR-0034, document schema 27) adds `siteURL` and
    /// `socialImageAssetID`. Version 1 records decode with both absent.
    /// Version 3 (SF-1107, ADR-0037, still document schema 27) adds site and
    /// page `customCode`. Version 2 records decode with it absent.
    static let currentVersion = 3
    static let versionWithoutCustomCode = 2
    static let versionWithoutSocialFields = 1
    let version: Int
    var siteName: String?
    var titlePattern: String?
    var defaultDescription: String?
    var faviconAssetID: AssetID?
    var allowsIndexing: Bool?
    var pages: [PageWebsiteMetadata]
    /// The published site's address, `https://host[/path]` without a trailing
    /// slash, query or fragment. Needed for absolute social and sitemap URLs.
    var siteURL: String?
    /// The image shared links show (Open Graph / Twitter card).
    var socialImageAssetID: AssetID?
    /// SF-1107: custom code written on every page of the static site.
    var customCode: CustomCodeBlock?

    init(siteName: String? = nil, titlePattern: String? = nil, defaultDescription: String? = nil,
         faviconAssetID: AssetID? = nil, allowsIndexing: Bool? = nil, pages: [PageWebsiteMetadata] = [],
         siteURL: String? = nil, socialImageAssetID: AssetID? = nil, customCode: CustomCodeBlock? = nil) {
        version = Self.currentVersion
        self.siteName = siteName; self.titlePattern = titlePattern; self.defaultDescription = defaultDescription
        self.faviconAssetID = faviconAssetID; self.allowsIndexing = allowsIndexing
        self.pages = pages.sorted { $0.pageID.description < $1.pageID.description }
        self.siteURL = siteURL; self.socialImageAssetID = socialImageAssetID
        self.customCode = customCode
    }
    var isEmpty: Bool {
        siteName == nil && titlePattern == nil && defaultDescription == nil
            && faviconAssetID == nil && allowsIndexing == nil && pages.isEmpty
            && siteURL == nil && socialImageAssetID == nil && customCode == nil
    }
    /// True when this record uses fields that need document schema 27.
    var usesSocialFields: Bool { siteURL != nil || socialImageAssetID != nil }
    /// True when the site or any page has custom code (also schema 27).
    var usesCustomCode: Bool { customCode != nil || pages.contains { $0.customCode != nil } }

    /// SF-1207-004: an absolute https address with a host, no credentials,
    /// port 443 only, no query, fragment or trailing slash, at most 512 bytes.
    static func validSiteURL(_ value: String?) -> Bool {
        guard let value else { return true }
        guard value.utf8.count <= 512, value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.hasSuffix("/"), value.rangeOfCharacter(from: .controlCharacters) == nil,
              !value.contains(" "), !value.contains("\""), !value.contains("<"),
              let components = URLComponents(string: value), components.scheme == "https",
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              components.port == nil || components.port == 443, components.query == nil, components.fragment == nil
        else { return false }
        return true
    }
    /// Empty page drafts mean inheritance, not an otherwise meaningless
    /// serialized override. Preserve every other page's authored metadata.
    func replacingPageOverride(_ override: PageWebsiteMetadata) -> Self {
        var result = self
        result.pages.removeAll { $0.pageID == override.pageID }
        if !override.isEmpty { result.pages.append(override) }
        result.pages.sort { $0.pageID.description < $1.pageID.description }
        return result
    }
    static func validText(_ value: String?, maximumBytes: Int) -> Bool {
        guard let value else { return true }
        return !value.isEmpty && value.utf8.count <= maximumBytes
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value == value.precomposedStringWithCanonicalMapping
            && value.rangeOfCharacter(from: .controlCharacters) == nil
    }
    var isValid: Bool {
        let remaining = (titlePattern ?? "").replacingOccurrences(of: "{page}", with: "")
            .replacingOccurrences(of: "{site}", with: "")
        return version == Self.currentVersion && Self.validText(siteName, maximumBytes: 256)
            && Self.validText(titlePattern, maximumBytes: 512)
            && Self.validText(defaultDescription, maximumBytes: 2_048)
            && !remaining.contains("{") && !remaining.contains("}")
            && Set(pages.map(\.pageID)).count == pages.count && pages.allSatisfy(\.isValid)
            && pages.map(\.pageID.description) == pages.map(\.pageID.description).sorted()
            && Self.validSiteURL(siteURL)
            && (customCode?.isValid ?? true)
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, siteName, titlePattern, defaultDescription, faviconAssetID, allowsIndexing, pages
        case siteURL, socialImageAssetID, customCode
    }
    /// The closed key set of a version 2 record.
    private enum VersionTwoCodingKeys: String, CodingKey, CaseIterable {
        case version, siteName, titlePattern, defaultDescription, faviconAssetID, allowsIndexing, pages
        case siteURL, socialImageAssetID
    }
    /// The closed key set of a version 1 record.
    private enum VersionOneCodingKeys: String, CodingKey, CaseIterable {
        case version, siteName, titlePattern, defaultDescription, faviconAssetID, allowsIndexing, pages
    }
    init(from decoder: Decoder) throws {
        let header = try decoder.container(keyedBy: AnySiteForgeCodingKey.self)
        guard let versionKey = AnySiteForgeCodingKey(stringValue: "version") else { throw ModelValidationError.invalidWebsiteMetadata }
        let storedVersion = try header.decode(Int.self, forKey: versionKey)
        switch storedVersion {
        case Self.versionWithoutSocialFields: try requireExactKeys(VersionOneCodingKeys.self, in: decoder)
        case Self.versionWithoutCustomCode: try requireExactKeys(VersionTwoCodingKeys.self, in: decoder)
        case Self.currentVersion: try requireExactKeys(CodingKeys.self, in: decoder)
        default: throw ModelValidationError.invalidWebsiteMetadata
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // An older record is read as the current version with the newer
        // fields absent, so it round-trips as version 3.
        version = Self.currentVersion
        siteName = try values.decodeIfPresent(String.self, forKey: .siteName)
        titlePattern = try values.decodeIfPresent(String.self, forKey: .titlePattern)
        defaultDescription = try values.decodeIfPresent(String.self, forKey: .defaultDescription)
        faviconAssetID = try values.decodeIfPresent(AssetID.self, forKey: .faviconAssetID)
        allowsIndexing = try values.decodeIfPresent(Bool.self, forKey: .allowsIndexing)
        pages = try values.decode([PageWebsiteMetadata].self, forKey: .pages)
        siteURL = try values.decodeIfPresent(String.self, forKey: .siteURL)
        socialImageAssetID = try values.decodeIfPresent(AssetID.self, forKey: .socialImageAssetID)
        customCode = try values.decodeIfPresent(CustomCodeBlock.self, forKey: .customCode)
        // Page custom code exists only in version 3 records.
        guard isValid, storedVersion == Self.currentVersion || !pages.contains(where: { $0.customCode != nil }) else {
            throw ModelValidationError.invalidWebsiteMetadata
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encode(siteName, forKey: .siteName)
        try values.encode(titlePattern, forKey: .titlePattern)
        try values.encode(defaultDescription, forKey: .defaultDescription)
        try values.encode(faviconAssetID, forKey: .faviconAssetID)
        try values.encode(allowsIndexing, forKey: .allowsIndexing)
        try values.encode(pages, forKey: .pages)
        try values.encode(siteURL, forKey: .siteURL)
        try values.encode(socialImageAssetID, forKey: .socialImageAssetID)
        try values.encode(customCode, forKey: .customCode)
    }
}

enum WebsiteMetadataSource: String, Equatable, Sendable {
    case authored, inherited, defaulted, omitted
    var presentation: String {
        switch self {
        case .authored: "Set here · this page"
        case .inherited: "Uses website default"
        case .defaulted: "Default · page name"
        case .omitted: "Not set"
        }
    }
}
struct ResolvedWebsiteMetadata: Equatable, Sendable {
    let siteName: String
    let title: String
    let description: String?
    let faviconAssetID: AssetID?
    let allowsIndexing: Bool
    let titleSource: WebsiteMetadataSource
    let descriptionSource: WebsiteMetadataSource
}
enum WebsiteMetadataResolver {
    /// `ignoresPageTitle` skips the page's own title (collection item pages
    /// take their title from the item through the title pattern).
    static func resolve(page: DocumentPage, document: CanonicalDocument,
                        ignoresPageTitle: Bool = false) -> ResolvedWebsiteMetadata {
        let metadata = document.websiteMetadata
        let overrides = metadata?.pages.first { $0.pageID == page.id }
        let pageTitle = ignoresPageTitle ? nil : overrides?.title
        let siteName = metadata?.siteName ?? document.pages.first(where: { $0.role == .home })?.name ?? "Untitled Site"
        let pattern = metadata?.titlePattern ?? "{page}"
        // Substitute once: an authored site/page name containing braces is text,
        // not a second template evaluation or executable expression.
        let title = pageTitle ?? pattern.components(separatedBy: "{page}")
            .map { $0.components(separatedBy: "{site}").joined(separator: siteName) }.joined(separator: page.name)
        return .init(siteName: siteName, title: title,
                     description: overrides?.description ?? metadata?.defaultDescription,
                     faviconAssetID: metadata?.faviconAssetID,
                     allowsIndexing: overrides?.allowsIndexing ?? metadata?.allowsIndexing ?? true,
                     titleSource: pageTitle != nil ? .authored : (metadata?.titlePattern != nil ? .inherited : .defaulted),
                     descriptionSource: overrides?.description != nil ? .authored
                        : (metadata?.defaultDescription != nil ? .inherited : .omitted))
    }
}

/// SF-0206-001/003/004: canonical project-scoped workspace preferences. Every
/// field is optional: an omitted field follows the next source (this Mac's
/// application default where one exists, then the SiteForge default), so "not
/// set in this project" stays distinct from an authored value that happens to
/// equal the default. Application preferences (appearance, new-workspace
/// defaults) never enter this record; see ADR-0027.
struct ProjectPreferences: Codable, Equatable, Sendable {
    static let currentVersion = 1
    /// The document schema that introduced project preferences. Older
    /// envelopes cannot carry the record.
    static let documentSchema = 22
    static let defaultGridSpacing = 16.0
    static let gridSpacingRange = 4.0...128.0
    /// Convenience choices offered by Settings; any whole value in range is valid.
    static let gridSpacingChoices: [Double] = [8, 10, 12, 16, 20, 24, 32, 40, 48]

    let version: Int
    /// Whether the editor Grid is shown when this project opens, or when this
    /// value changes. The scene-local Grid toggle never writes this field.
    var gridVisibleOnOpen: Bool?
    /// Minor world-grid interval in points at 100% zoom; major lines are 4x.
    var gridSpacing: Double?
    /// SF-1208-001 / SF-1211-001 (OD-042, ADR-0122): saved build settings; omitted when unset.
    var build: BuildProfileSettings?

    init(gridVisibleOnOpen: Bool? = nil, gridSpacing: Double? = nil, build: BuildProfileSettings? = nil) {
        version = Self.currentVersion
        self.gridVisibleOnOpen = gridVisibleOnOpen
        self.gridSpacing = gridSpacing
        self.build = build
    }

    var isEmpty: Bool { gridVisibleOnOpen == nil && gridSpacing == nil && build == nil }

    /// Every value satisfies its rule. New commits must not introduce a value
    /// that fails this check (SF-0206-004).
    var isValid: Bool { isStructurallyValid && invalidPreferenceIDs.isEmpty && (build?.isValid ?? true) }

    /// SF-0206-004: what a project file must satisfy to open. A stored value
    /// that breaks its value rule (for example spacing outside 4–128 pt) keeps
    /// the project openable: the value is retained, resolution falls back to
    /// the SiteForge default, and Settings states the rule and offers repair.
    var isStructurallyValid: Bool {
        version == Self.currentVersion && (gridSpacing?.isFinite ?? true)
            // An empty build record is never stored (ADR-0122).
            && (build.map { $0.isStructurallyValid && !$0.isEmpty } ?? true)
    }

    /// Stored values that break their rule, by stable preference identity.
    var invalidPreferenceIDs: [ProjectPreferenceID] {
        guard let gridSpacing, !Self.isValidGridSpacing(gridSpacing) else { return [] }
        return [.gridSpacing]
    }

    /// Stable identities of the fields that differ from `other`.
    func changedPreferenceIDs(from other: ProjectPreferences?) -> [ProjectPreferenceID] {
        ProjectPreferenceID.allCases.filter { id in
            switch id {
            case .gridVisibleOnOpen: gridVisibleOnOpen != other?.gridVisibleOnOpen
            case .gridSpacing: gridSpacing != other?.gridSpacing
            }
        }
    }

    static func isValidGridSpacing(_ value: Double) -> Bool {
        value.isFinite && gridSpacingRange.contains(value) && value.rounded() == value
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case version, gridVisibleOnOpen, gridSpacing, build }

    init(from decoder: Decoder) throws {
        try requireKnownKeys(CodingKeys.self, in: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // An unset preference is omitted, never stored as null.
        for key in [CodingKeys.gridVisibleOnOpen, .gridSpacing, .build] where values.contains(key) {
            guard try !values.decodeNil(forKey: key) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: values,
                    debugDescription: "Omit an unset project preference instead of storing null.")
            }
        }
        version = try values.decode(Int.self, forKey: .version)
        gridVisibleOnOpen = try values.decodeIfPresent(Bool.self, forKey: .gridVisibleOnOpen)
        gridSpacing = try values.decodeIfPresent(Double.self, forKey: .gridSpacing)
        build = try values.decodeIfPresent(BuildProfileSettings.self, forKey: .build)
        guard version == Self.currentVersion else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: values,
                debugDescription: "Unsupported project preferences version.")
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encodeIfPresent(gridVisibleOnOpen, forKey: .gridVisibleOnOpen)
        try values.encodeIfPresent(gridSpacing, forKey: .gridSpacing)
        try values.encodeIfPresent(build, forKey: .build)
    }
}

/// SF-1208-001/003 and SF-1211-001/003 (OD-042, ADR-0122): the project's saved
/// build settings. They live inside `ProjectPreferences` (schema 22+ key), so
/// they share its one undoable command, persisted history, snapshot restore and
/// comparison; no `CanonicalDocument` key is added. Every field is optional: an
/// omitted field follows the SiteForge default (`BuildSettingsResolver`), so
/// "not set in this project" stays distinct from an authored value that equals
/// the default. Budgets are whole kilobytes (1 KB = 1,024 bytes); an authored 0
/// means "no limit". A stored budget that breaks its rule keeps the project
/// openable: it is retained, the SiteForge default is used, and Check Website
/// names the rule.
struct BuildProfileSettings: Codable, Equatable, Sendable {
    static let currentVersion = 1
    /// OD-120 recommended defaults (open decision), used only when the project stores no value.
    static let defaultPageBudgetKilobytes = 256
    static let defaultAssetBudgetKilobytes = 5_120
    static let defaultTotalBudgetKilobytes = 51_200
    /// 10 GB; a local static build cannot usefully promise more.
    static let maximumBudgetKilobytes = 10_485_760

    let version: Int
    /// The profile Check Website starts with when this project opens.
    var profile: LocalBuildProfile?
    /// Largest allowed generated page (`.html`).
    var pageBudgetKilobytes: Int?
    /// Largest allowed single file under `assets/` (images, fonts, video, audio).
    var assetBudgetKilobytes: Int?
    /// Largest allowed total of every written file.
    var totalBudgetKilobytes: Int?
    var releasePolicy: BuildReleasePolicy?
    /// SF-1107-004 / SF-1211-003 (OD-041, ADR-0037 amendment): SHA-256 of the
    /// custom code the author marked as reviewed (`CustomCodeReview.digest`),
    /// never the code itself. It counts only while it matches the current code.
    var reviewedCustomCodeDigest: String?

    init(profile: LocalBuildProfile? = nil, pageBudgetKilobytes: Int? = nil, assetBudgetKilobytes: Int? = nil,
         totalBudgetKilobytes: Int? = nil, releasePolicy: BuildReleasePolicy? = nil,
         reviewedCustomCodeDigest: String? = nil) {
        version = Self.currentVersion
        self.profile = profile
        self.pageBudgetKilobytes = pageBudgetKilobytes
        self.assetBudgetKilobytes = assetBudgetKilobytes
        self.totalBudgetKilobytes = totalBudgetKilobytes
        self.releasePolicy = releasePolicy
        self.reviewedCustomCodeDigest = reviewedCustomCodeDigest
    }

    var isEmpty: Bool {
        profile == nil && pageBudgetKilobytes == nil && assetBudgetKilobytes == nil
            && totalBudgetKilobytes == nil && releasePolicy == nil && reviewedCustomCodeDigest == nil
    }

    /// The same record with every build setting at its SiteForge default but the
    /// custom code review kept: Use SiteForge Defaults resets settings, it does
    /// not withdraw the author's review of their code (ADR-0037 amendment).
    var keepingCustomCodeReview: BuildProfileSettings {
        BuildProfileSettings(reviewedCustomCodeDigest: reviewedCustomCodeDigest)
    }

    /// What a project file must satisfy to open.
    var isStructurallyValid: Bool { version == Self.currentVersion }

    /// Stored budgets that break their rule, by stable setting identity.
    var invalidSettingIDs: [BuildSettingID] {
        BuildBudgetKind.allCases.compactMap { kind -> BuildSettingID? in
            guard let value = budget(kind), !Self.isValidBudget(value) else { return nil }
            return kind.settingID
        }
    }

    var isValid: Bool { isStructurallyValid && invalidSettingIDs.isEmpty }

    static func isValidBudget(_ kilobytes: Int) -> Bool { (0...maximumBudgetKilobytes).contains(kilobytes) }

    func budget(_ kind: BuildBudgetKind) -> Int? {
        switch kind {
        case .page: pageBudgetKilobytes
        case .asset: assetBudgetKilobytes
        case .total: totalBudgetKilobytes
        }
    }

    mutating func setBudget(_ kind: BuildBudgetKind, _ kilobytes: Int?) {
        switch kind {
        case .page: pageBudgetKilobytes = kilobytes
        case .asset: assetBudgetKilobytes = kilobytes
        case .total: totalBudgetKilobytes = kilobytes
        }
    }

    /// Stable identities of the settings that differ from `other`.
    func changedSettingIDs(from other: BuildProfileSettings?) -> [BuildSettingID] {
        BuildSettingID.allCases.filter { id in
            switch id {
            case .profile: profile != other?.profile
            case .pageBudget: pageBudgetKilobytes != other?.pageBudgetKilobytes
            case .assetBudget: assetBudgetKilobytes != other?.assetBudgetKilobytes
            case .totalBudget: totalBudgetKilobytes != other?.totalBudgetKilobytes
            case .releasePolicy: releasePolicy != other?.releasePolicy
            case .customCodeReview: reviewedCustomCodeDigest != other?.reviewedCustomCodeDigest
            }
        }
    }

    /// SF-1208-004: true when this value would commit a budget that breaks its
    /// rule and is not the project's own stored value. An untouched stored value
    /// is retained so the other settings stay editable.
    func introducesInvalidBudget(comparedWith stored: BuildProfileSettings?) -> Bool {
        BuildBudgetKind.allCases.contains { kind in
            guard let value = budget(kind), !Self.isValidBudget(value) else { return false }
            return value != stored?.budget(kind)
        }
    }

    /// Convenience choices Check Website offers (0 is "No limit"); the
    /// project's own stored value is always offered so it can be kept.
    static func budgetChoices(_ kind: BuildBudgetKind, including current: Int? = nil) -> [Int] {
        var values: [Int] = switch kind {
        case .page: [0, 64, 128, 256, 512, 1_024, 2_048]
        case .asset: [0, 256, 512, 1_024, 2_048, 5_120, 10_240, 16_384]
        case .total: [0, 5_120, 10_240, 25_600, 51_200, 102_400, 512_000, 1_048_576]
        }
        if let current, !values.contains(current) { values.append(current) }
        return values.sorted()
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, profile, pageBudgetKilobytes, assetBudgetKilobytes, totalBudgetKilobytes, releasePolicy
        case reviewedCustomCodeDigest
    }

    init(from decoder: Decoder) throws {
        try requireKnownKeys(CodingKeys.self, in: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // An unset build setting is omitted, never stored as null.
        for key in CodingKeys.allCases where key != .version && values.contains(key) {
            guard try !values.decodeNil(forKey: key) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: values,
                    debugDescription: "Omit an unset build setting instead of storing null.")
            }
        }
        version = try values.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: values,
                debugDescription: "Unsupported build settings version.")
        }
        profile = try values.decodeIfPresent(LocalBuildProfile.self, forKey: .profile)
        pageBudgetKilobytes = try values.decodeIfPresent(Int.self, forKey: .pageBudgetKilobytes)
        assetBudgetKilobytes = try values.decodeIfPresent(Int.self, forKey: .assetBudgetKilobytes)
        totalBudgetKilobytes = try values.decodeIfPresent(Int.self, forKey: .totalBudgetKilobytes)
        releasePolicy = try values.decodeIfPresent(BuildReleasePolicy.self, forKey: .releasePolicy)
        reviewedCustomCodeDigest = try values.decodeIfPresent(String.self, forKey: .reviewedCustomCodeDigest)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encodeIfPresent(profile, forKey: .profile)
        try values.encodeIfPresent(pageBudgetKilobytes, forKey: .pageBudgetKilobytes)
        try values.encodeIfPresent(assetBudgetKilobytes, forKey: .assetBudgetKilobytes)
        try values.encodeIfPresent(totalBudgetKilobytes, forKey: .totalBudgetKilobytes)
        try values.encodeIfPresent(releasePolicy, forKey: .releasePolicy)
        try values.encodeIfPresent(reviewedCustomCodeDigest, forKey: .reviewedCustomCodeDigest)
    }
}

/// SF-1107-004 / SF-1211-003 (OD-041, OD-042, ADR-0037 amendment): the author's
/// acknowledgement that the website's custom code, exactly as it is now, was
/// reviewed. Custom code is never checked, so under "Block Static Release on
/// warnings" its warnings would otherwise block release until the code is
/// deleted. A reviewed digest turns those findings into information (still
/// shown) so the release can proceed. Only the digest is stored, in the build
/// settings; any change to any block changes the digest, which ends the review
/// without rewriting the project.
enum CustomCodeReview {
    enum Status: Equatable, Sendable {
        case noCustomCode, notReviewed, reviewed, changedSinceReview
    }

    /// Nil when the website has no custom code. Covers the site block and every
    /// page block with its page identity, field by field with byte lengths, so
    /// moving code to another field or page also needs a new review.
    static func digest(_ metadata: WebsiteMetadata?) -> String? {
        guard let metadata, metadata.usesCustomCode else { return nil }
        var bytes = Data()
        func append(_ scope: String, _ block: CustomCodeBlock?) {
            guard let block else { return }
            let fields: [(String, String?)] = [("head", block.headHTML), ("body", block.bodyHTML), ("css", block.css)]
            for (name, field) in fields {
                let header = field.map { "\(scope).\(name):\($0.utf8.count):" } ?? "\(scope).\(name):-:"
                bytes.append(Data(header.utf8))
                if let field { bytes.append(Data(field.utf8)) }
            }
        }
        append("site", metadata.customCode)
        for entry in metadata.pages.sorted(by: { $0.pageID.description < $1.pageID.description }) {
            append("page-" + entry.pageID.description, entry.customCode)
        }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    static func status(_ document: CanonicalDocument) -> Status {
        guard let current = digest(document.websiteMetadata) else { return .noCustomCode }
        guard let reviewed = document.projectPreferences?.build?.reviewedCustomCodeDigest else { return .notReviewed }
        return reviewed == current ? .reviewed : .changedSinceReview
    }

    static func isReviewed(_ document: CanonicalDocument) -> Bool { status(document) == .reviewed }
}

/// SF-1211-003 (OD-042, ADR-0122): whether warnings stop Static Release from writing.
enum BuildReleasePolicy: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Only errors stop writing (the SiteForge default; OD-120).
    case errorsOnly = "errors-only"
    /// Static Release also refuses to write while any warning remains.
    /// Development is never blocked by warnings.
    case warningsBlockRelease = "warnings-block-release"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .errorsOnly: "Block on errors only"
        case .warningsBlockRelease: "Block Static Release on warnings"
        }
    }
}

/// SF-1208-008 (ADR-0122): stable identity of each build setting. Diagnostics
/// name these identifiers, never the stored values.
enum BuildSettingID: String, CaseIterable, Sendable {
    case profile = "project.build.profile"
    case pageBudget = "project.build.pageBudget"
    case assetBudget = "project.build.assetBudget"
    case totalBudget = "project.build.totalBudget"
    case releasePolicy = "project.build.releasePolicy"
    /// ADR-0037 amendment: the custom code review (a digest, never the code).
    case customCodeReview = "project.build.customCodeReview"

    var title: String {
        switch self {
        case .profile: "Profile when the project opens"
        case .pageBudget: "Page budget"
        case .assetBudget: "Asset budget"
        case .totalBudget: "Site budget"
        case .releasePolicy: "Release policy"
        case .customCodeReview: "Custom code review"
        }
    }
}

/// SF-1211 (ADR-0122): the three size budgets a build is checked against.
enum BuildBudgetKind: String, CaseIterable, Sendable {
    case page, asset, total

    var settingID: BuildSettingID {
        switch self {
        case .page: .pageBudget
        case .asset: .assetBudget
        case .total: .totalBudget
        }
    }
    var title: String { settingID.title }
    var findingCode: String { "budget-\(rawValue)-exceeded" }
    var defaultKilobytes: Int {
        switch self {
        case .page: BuildProfileSettings.defaultPageBudgetKilobytes
        case .asset: BuildProfileSettings.defaultAssetBudgetKilobytes
        case .total: BuildProfileSettings.defaultTotalBudgetKilobytes
        }
    }
}

/// SF-1208-003 / SF-1211-003 (ADR-0122): deterministic precedence. A valid
/// authored project value wins, then the SiteForge default. A stored value that
/// breaks its rule resolves as `invalidProjectValue` with the default. The
/// resolver never mutates or normalizes stored data.
enum BuildSettingsResolver {
    static func profile(_ settings: BuildProfileSettings?) -> ProjectPreferenceResolution<LocalBuildProfile> {
        if let value = settings?.profile { return .init(value: value, source: .project) }
        return .init(value: .development, source: .builtIn)
    }

    static func budget(_ kind: BuildBudgetKind, _ settings: BuildProfileSettings?) -> ProjectPreferenceResolution<Int> {
        guard let value = settings?.budget(kind) else { return .init(value: kind.defaultKilobytes, source: .builtIn) }
        guard BuildProfileSettings.isValidBudget(value) else {
            return .init(value: kind.defaultKilobytes, source: .invalidProjectValue)
        }
        return .init(value: value, source: .project)
    }

    static func releasePolicy(_ settings: BuildProfileSettings?) -> ProjectPreferenceResolution<BuildReleasePolicy> {
        if let value = settings?.releasePolicy { return .init(value: value, source: .project) }
        return .init(value: .errorsOnly, source: .builtIn)
    }

    /// SF-1208-003: names the rule that supplied a value.
    static func sourceTitle(_ source: ProjectPreferenceSource) -> String {
        switch source {
        case .project: "Set in this project"
        case .application, .builtIn: "SiteForge default"
        case .invalidProjectValue:
            "The saved value breaks its rule (whole KB from 0 through 10,485,760), so the SiteForge default is used"
        }
    }

    static func budgetLabel(_ kilobytes: Int) -> String {
        guard kilobytes > 0 else { return "No limit" }
        return kilobytes % 1_024 == 0 ? "\(kilobytes / 1_024) MB" : "\(kilobytes) KB"
    }
}

/// SF-0206-001/004: stable identity of each project preference. Diagnostics
/// and recovery name these identifiers, never the stored values.
enum ProjectPreferenceID: String, CaseIterable, Sendable {
    case gridVisibleOnOpen = "project.canvas.gridVisibleOnOpen"
    case gridSpacing = "project.canvas.gridSpacing"

    var title: String {
        switch self {
        case .gridVisibleOnOpen: "Grid when the project opens"
        case .gridSpacing: "Grid spacing"
        }
    }
}

/// SF-0206-003: the rule that supplied an effective project preference.
/// `invalidProjectValue` means the project stores a value that breaks its rule;
/// the SiteForge default is used until the user repairs it.
enum ProjectPreferenceSource: String, Equatable, Sendable {
    case project, application, builtIn, invalidProjectValue
}

struct ProjectPreferenceResolution<Value: Equatable & Sendable>: Equatable, Sendable {
    let value: Value
    let source: ProjectPreferenceSource
}

/// SF-0206-003: deterministic precedence. An authored project value wins,
/// then this Mac's application default (only where one exists), then the
/// SiteForge default. The resolver never mutates or normalizes stored data.
enum ProjectPreferenceResolver {
    static func gridVisibleOnOpen(_ preferences: ProjectPreferences?, applicationDefault: Bool?)
        -> ProjectPreferenceResolution<Bool> {
        if let value = preferences?.gridVisibleOnOpen { return .init(value: value, source: .project) }
        if let value = applicationDefault { return .init(value: value, source: .application) }
        return .init(value: true, source: .builtIn)
    }

    static func gridSpacing(_ preferences: ProjectPreferences?) -> ProjectPreferenceResolution<Double> {
        guard let value = preferences?.gridSpacing else {
            return .init(value: ProjectPreferences.defaultGridSpacing, source: .builtIn)
        }
        guard ProjectPreferences.isValidGridSpacing(value) else {
            return .init(value: ProjectPreferences.defaultGridSpacing, source: .invalidProjectValue)
        }
        return .init(value: value, source: .project)
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
    var colorTokens: [LocalColorToken]
    var websiteMetadata: WebsiteMetadata?
    /// SF-0206-001: optional project-scoped preferences (schema 22+).
    var projectPreferences: ProjectPreferences?
    /// OD-035 / SF-1001: local CMS collections (schema 27). The key is written
    /// only when there is at least one collection.
    var collections: [ContentCollection]
    /// OD-045 / SF-0805: project font faces (schema 27). The key is written
    /// only when there is at least one font.
    var fontAssets: [FontAsset]
    /// OD-038 / SF-1007-001: the site's languages (schema 27). The key is
    /// written only when the site is localized.
    var localization: SiteLocalization?
    /// OD-045 / SF-0803: project video, audio and captions files (schema 27).
    /// The key is written only when there is at least one file.
    var mediaAssets: [MediaAsset]

    init(
        id: DocumentID = DocumentID(),
        revision: UInt64 = 0,
        creationKind: ProjectCreationKind = .blank,
        templateID: TemplateID? = nil,
        pages: [DocumentPage]? = nil,
        guides: [AuthoredGuide] = [],
        imageAssets: [ImageAsset] = [],
        colorTokens: [LocalColorToken] = [],
        websiteMetadata: WebsiteMetadata? = nil,
        projectPreferences: ProjectPreferences? = nil,
        collections: [ContentCollection] = [],
        fontAssets: [FontAsset] = [],
        localization: SiteLocalization? = nil,
        mediaAssets: [MediaAsset] = []
    ) {
        self.id = id
        self.revision = revision
        self.creationKind = creationKind
        self.templateID = templateID
        self.pages = pages ?? BlankProjectDefaults.pages()
        self.guides = guides
        self.imageAssets = imageAssets
        self.colorTokens = colorTokens
        self.websiteMetadata = websiteMetadata
        self.projectPreferences = projectPreferences
        self.collections = collections
        self.fontAssets = fontAssets
        self.localization = localization
        self.mediaAssets = mediaAssets
    }


    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, revision, creationKind, templateID, pages, guides, imageAssets, colorTokens, websiteMetadata, projectPreferences
        case collections
        case fontAssets
        case localization
        case mediaAssets
    }
    private enum MetadataCodingKeys: String, CodingKey, CaseIterable {
        case id, revision, creationKind, templateID, pages, guides, imageAssets, colorTokens, websiteMetadata
    }
    private enum PreMetadataCodingKeys: String, CodingKey, CaseIterable {
        case id, revision, creationKind, templateID, pages, guides, imageAssets, colorTokens
    }

    init(from decoder: Decoder) throws {
        let sourceSchema = decoder.userInfo[SiteForgeDecodingPolicy.sourceDocumentSchema] as? Int
        let strict = SiteForgeDecodingPolicy.requiresExactKeys(decoder)
        if (sourceSchema ?? 18) < 18 {
            try requireExactKeys(PreMetadataCodingKeys.self, in: decoder, when: strict)
        } else if (sourceSchema ?? ProjectPreferences.documentSchema) < ProjectPreferences.documentSchema {
            // Schemas 18–21 cannot carry project preferences.
            try requireExactKeys(MetadataCodingKeys.self, in: decoder, when: strict)
        } else if strict {
            // SF-0206-001: the optional record is omitted when nothing is set.
            let actual = Set(try decoder.container(keyedBy: AnySiteForgeCodingKey.self).allKeys.map(\.stringValue))
            let required = Set(MetadataCodingKeys.allCases.map(\.stringValue))
            // OD-035: collections are optional too and omitted when empty.
            let optional = Set([CodingKeys.projectPreferences.stringValue, CodingKeys.collections.stringValue,
                                CodingKeys.fontAssets.stringValue, CodingKeys.localization.stringValue,
                                CodingKeys.mediaAssets.stringValue])
            guard required.isSubset(of: actual), actual.subtracting(required).isSubset(of: optional) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                    debugDescription: "Current SiteForge schema requires an exact closed key set."))
            }
        }
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
        colorTokens = try container.decode([LocalColorToken].self, forKey: .colorTokens)
        websiteMetadata = try container.decodeIfPresent(WebsiteMetadata.self, forKey: .websiteMetadata)
        if container.contains(.projectPreferences), try container.decodeNil(forKey: .projectPreferences) {
            throw DecodingError.dataCorruptedError(forKey: .projectPreferences, in: container,
                debugDescription: "Omit project preferences instead of storing null.")
        }
        projectPreferences = try container.decodeIfPresent(ProjectPreferences.self, forKey: .projectPreferences)
        if container.contains(.collections) {
            let stored = try container.decodeIfPresent([ContentCollection].self, forKey: .collections)
            guard let stored, !stored.isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .collections, in: container,
                    debugDescription: "Omit collections instead of storing null or an empty list.")
            }
            collections = stored
        } else {
            collections = []
        }
        // OD-045 / SF-0805: like collections, omitted when empty.
        if container.contains(.fontAssets) {
            let stored = try container.decodeIfPresent([FontAsset].self, forKey: .fontAssets)
            guard let stored, !stored.isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .fontAssets, in: container,
                    debugDescription: "Omit fonts instead of storing null or an empty list.")
            }
            fontAssets = stored
        } else {
            fontAssets = []
        }
        // OD-038 / SF-1007-001: omitted while the site has one unnamed language.
        if container.contains(.localization), try container.decodeNil(forKey: .localization) {
            throw DecodingError.dataCorruptedError(forKey: .localization, in: container,
                debugDescription: "Omit site languages instead of storing null.")
        }
        localization = try container.decodeIfPresent(SiteLocalization.self, forKey: .localization)
        // OD-045 / SF-0803: like fonts, omitted when empty.
        if container.contains(.mediaAssets) {
            let stored = try container.decodeIfPresent([MediaAsset].self, forKey: .mediaAssets)
            guard let stored, !stored.isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .mediaAssets, in: container,
                    debugDescription: "Omit video and audio files instead of storing null or an empty list.")
            }
            mediaAssets = stored
        } else {
            mediaAssets = []
        }
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
        try container.encode(colorTokens, forKey: .colorTokens)
        try container.encode(websiteMetadata, forKey: .websiteMetadata)
        try container.encodeIfPresent(projectPreferences, forKey: .projectPreferences)
        if !collections.isEmpty { try container.encode(collections, forKey: .collections) }
        if !fontAssets.isEmpty { try container.encode(fontAssets, forKey: .fontAssets) }
        try container.encodeIfPresent(localization, forKey: .localization)
        if !mediaAssets.isEmpty { try container.encode(mediaAssets, forKey: .mediaAssets) }
    }
}

/// SF-0901: definitions reuse the ordered canonical graph, but have no route.
/// References may be missing so damage never silently replaces authored intent.
enum CanonicalComponentReference {
    static let namespace = "component.instance.v1."
    static let key = namespace + "definitionID"

    static func definitionID(for node: DocumentNode) -> PageID? {
        guard node.kind == .component,
              let property = node.properties.first(where: { $0.key.rawValue == key }),
              case .string(let value) = property.value else { return nil }
        return PageID(uuidString: value)
    }

    static func validate(_ node: DocumentNode) throws {
        let properties = node.properties.filter { $0.key.rawValue.hasPrefix("component.") }
        guard !properties.isEmpty else { return }
        if node.kind != .component, properties.allSatisfy({
            $0.key.rawValue.hasPrefix(CanonicalComponentText.namespace)
                || $0.key.rawValue.hasPrefix(CanonicalComponentVisibility.namespace)
                || $0.key.rawValue.hasPrefix(CanonicalComponentChoice.namespace)
                || $0.key.rawValue.hasPrefix(CanonicalComponentMedia.namespace)
                || $0.key.rawValue.hasPrefix(CanonicalComponentAction.namespace)
                || $0.key.rawValue.hasPrefix(CanonicalComponentSlot.namespace)
                || $0.key.rawValue.hasPrefix(CanonicalComponentOrganization.namespace)
                || $0.key.rawValue == CanonicalComponentSlot.supplyKey
                || $0.key.rawValue.hasPrefix(CanonicalComponentVariants.namespace)
                || CanonicalComponentUsageNotes.owns($0)
        }) {
            // The definition-scoped validators own exposed bindings; supplied
            // membership is checked by `CanonicalComponentSlot.validateContent`.
            return
        }
        guard node.kind == .component, properties.contains(where: { $0.key.rawValue == key }),
              properties.allSatisfy({ $0.key.rawValue == key
                  || CanonicalComponentText.overrideID($0.key.rawValue) != nil
                  || CanonicalComponentVisibility.overrideID($0.key.rawValue) != nil
                  || CanonicalComponentChoice.overrideID($0.key.rawValue) != nil
                  || CanonicalComponentMedia.overrideID($0.key.rawValue) != nil
                  || CanonicalComponentAction.overrideID($0.key.rawValue) != nil
                  || CanonicalComponentSlot.overrideID($0.key.rawValue) != nil
                  // A supplied root may itself be an instance (OD-018).
                  || $0.key.rawValue == CanonicalComponentSlot.supplyKey
                  // OD-033: a copy's variant choices, and variant overrides on
                  // an instance placed inside a definition.
                  || CanonicalComponentVariants.isChoiceKey($0.key.rawValue)
                  || CanonicalComponentVariants.isOverrideKey($0.key.rawValue) }),
              definitionID(for: node) != nil else {
            // Children are supplied slot content; `validateContent` owns them.
            throw ModelValidationError.invalidComponentReference
        }
    }
}

/// SF-0901-003/004/007, OD-034 (ADR-0018 amendment, document schema 24):
/// the dependency graph of component definitions. A definition depends on
/// every definition that one of its own instances links to. Every valid
/// document keeps this graph acyclic, keeps each chain within
/// `maximumNestingDepth` definitions (outermost included), and keeps the fully
/// expanded size of every definition within the shared resolved-graph budget.
/// A link to a missing definition stays representable: it adds no dependency
/// and counts as the one placeholder object the instance draws.
struct CanonicalComponentGraph: Equatable, Sendable {
    static let documentSchema = 24
    static let maximumNestingDepth = 8

    /// Definitions in document order.
    let order: [PageID]
    /// Direct dependencies of each existing definition, unique, in the order
    /// their first instance appears in the definition's node list.
    let dependencies: [PageID: [PageID]]
    let names: [PageID: String]
    /// The first dependency cycle in document order, its first definition
    /// repeated at the end (`[A, B, A]`); `nil` when the graph is acyclic.
    let cycle: [PageID]?
    /// Instance links inside each definition, counted (missing targets kept).
    private let instanceCounts: [PageID: [PageID: Int]]
    private let depths: [PageID: Int]
    private let deepestDependency: [PageID: PageID]
    private let expandedObjects: [PageID: Int]

    init(document: CanonicalDocument) { self.init(definitions: document.componentDefinitions) }

    init(definitions: [DocumentPage]) {
        let definitions = definitions.filter { $0.role == .componentDefinition }
        var order: [PageID] = [], names: [PageID: String] = [:], sizes: [PageID: Int] = [:]
        var targets: [PageID: [PageID]] = [:]
        for definition in definitions where names[definition.id] == nil {
            order.append(definition.id)
            names[definition.id] = definition.name
            sizes[definition.id] = definition.nodes.count
            targets[definition.id] = definition.nodes.compactMap(CanonicalComponentReference.definitionID)
        }
        var dependencies: [PageID: [PageID]] = [:]
        for id in order {
            var seen = Set<PageID>()
            dependencies[id] = targets[id, default: []].filter { names[$0] != nil && seen.insert($0).inserted }
        }
        self.order = order
        self.names = names
        self.dependencies = dependencies
        self.instanceCounts = targets.mapValues { links in links.reduce(into: [:]) { $0[$1, default: 0] += 1 } }
        let cycle = Self.firstCycle(order: order, dependencies: dependencies)
        self.cycle = cycle
        if cycle == nil {
            let measured = Self.measure(order: order, dependencies: dependencies, targets: targets, sizes: sizes)
            depths = measured.depths
            deepestDependency = measured.deepest
            expandedObjects = measured.objects
        } else {
            depths = [:]; deepestDependency = [:]; expandedObjects = [:]
        }
    }

    /// Number of definitions in the deepest chain that starts at `id`
    /// (1 when it contains no instance of an existing definition). `nil` for
    /// an unknown definition or while the graph has a cycle.
    func nestingDepth(of id: PageID) -> Int? { depths[id] }

    /// The deepest chain that starts at `id`, outermost first.
    func deepestChain(from id: PageID) -> [PageID] {
        guard depths[id] != nil else { return [] }
        var chain = [id], current = id
        while let next = deepestDependency[current], chain.count <= order.count {
            chain.append(next); current = next
        }
        return chain
    }

    /// Objects one instance of `id` resolves to, nested instances expanded.
    /// Saturates at `ResolvedGraphPolicy.maximumNodes + 1`.
    func expandedObjectCount(of id: PageID) -> Int? { expandedObjects[id] }

    /// Every definition that contains `id`, directly or through other
    /// definitions. Safe on cyclic graphs.
    func dependents(of id: PageID) -> Set<PageID> {
        var users: [PageID: [PageID]] = [:]
        for owner in order { for dependency in dependencies[owner, default: []] { users[dependency, default: []].append(owner) } }
        var result = Set<PageID>(), pending = [id]
        while let next = pending.popLast() {
            for owner in users[next, default: []] where result.insert(owner).inserted { pending.append(owner) }
        }
        return result
    }

    /// Every instance that website output contains: instances on website
    /// pages, then instances inside each definition those pages use, directly
    /// or indirectly (definitions in document order). Preview, Browser Preview
    /// and export apply the same recovery checks to all of them.
    static func outputInstances(in document: CanonicalDocument) -> [DocumentNode] {
        let pageInstances = document.websitePages.flatMap(\.nodes).filter { $0.kind == .component }
        let used = CanonicalComponentGraph(document: document)
            .dependencyClosure(of: Set(pageInstances.compactMap(CanonicalComponentReference.definitionID)))
        return pageInstances + document.componentDefinitions.filter { used.contains($0.id) }
            .flatMap(\.nodes).filter { $0.kind == .component }
    }

    /// The rule the graph would break after adding one instance of each of
    /// `targets` inside definition `definitionID`, or `nil`. `nil` when
    /// `definitionID` is not one of `definitions` (pages never nest).
    static func violation(adding targets: [PageID], into definitionID: PageID,
                          definitions: [DocumentPage]) -> ComponentGraphViolation? {
        guard !targets.isEmpty,
              let index = definitions.firstIndex(where: { $0.id == definitionID && $0.role == .componentDefinition }),
              let rootID = definitions[index].rootNodeIDs.first else { return nil }
        var probed = definitions
        for target in targets {
            probed[index].nodes.append(DocumentNode(kind: .component, name: "Insertion", parent: .node(rootID),
                properties: [NodeProperty(key: .init(rawValue: CanonicalComponentReference.key),
                                          value: .string(target.description))]))
        }
        return CanonicalComponentGraph(definitions: probed).violation
    }

    /// For every definition D, the rule one instance of D placed inside
    /// `target` would break; a definition absent from the result can be
    /// inserted. Same answer as `violation(adding: [D], into: target, …)` for
    /// each D, decided in one pass over the graph (SF-0901-007): D breaks a
    /// rule only if it already contains `target` (cycle), if the longest chain
    /// down to `target` plus D's own depth exceeds the limit, or if a user of
    /// `target` would grow past the object budget. Only those D are rebuilt,
    /// to report the exact rule and chain.
    func insertionViolations(into target: PageID, definitions: [DocumentPage]) -> [PageID: ComponentGraphViolation] {
        guard names[target] != nil else { return [:] }
        func exact(_ ids: [PageID]) -> [PageID: ComponentGraphViolation] {
            var result: [PageID: ComponentGraphViolation] = [:]
            for id in ids {
                if let violation = Self.violation(adding: [id], into: target, definitions: definitions) { result[id] = violation }
            }
            return result
        }
        guard violation == nil else { return exact(order) }
        let users = dependents(of: target).union([target])
        // Longest chain (in definitions) from each user down to `target`, and
        // how many instances of `target` one fully expanded user contains.
        let limit = ResolvedGraphPolicy.maximumNodes + 1
        var chain: [PageID: Int] = [target: 1], copies: [PageID: Int] = [target: 1]
        var stack: [(PageID, Bool)] = users.subtracting([target]).sorted { $0.description < $1.description }.map { ($0, false) }
        while let (id, exiting) = stack.popLast() {
            guard chain[id] == nil else { continue }
            let inner = dependencies[id, default: []].filter(users.contains)
            guard exiting else {
                stack.append((id, true))
                for next in inner where chain[next] == nil { stack.append((next, false)) }
                continue
            }
            chain[id] = 1 + (inner.compactMap { chain[$0] }.max() ?? 0)
            var total = 0
            for next in inner {
                let links = instanceCounts[id]?[next] ?? 0
                total = min(limit, total + min(limit, links * (copies[next] ?? 0)))
            }
            copies[id] = total
        }
        let longestChain = chain.values.max() ?? 1
        let roomForInsertion = users.compactMap { id -> Int? in
            guard let count = copies[id], count > 0, let size = expandedObjects[id] else { return nil }
            return max(0, ResolvedGraphPolicy.maximumNodes - size) / count
        }.min() ?? ResolvedGraphPolicy.maximumNodes
        return exact(order.filter { id in
            users.contains(id)
                || longestChain + (depths[id] ?? 0) > Self.maximumNestingDepth
                || (expandedObjects[id] ?? 0) > roomForInsertion
        })
    }

    /// Every definition, each after the definitions it contains, otherwise in
    /// document order. Used to import inner definitions before outer ones.
    /// Terminates on cyclic graphs (a cycle is broken at its first revisit).
    func dependenciesFirst() -> [PageID] {
        var result: [PageID] = [], placed = Set<PageID>(), entered = Set<PageID>()
        for start in order where !placed.contains(start) {
            var stack: [(PageID, Bool)] = [(start, false)]
            while let (id, exiting) = stack.popLast() {
                if exiting {
                    if placed.insert(id).inserted { result.append(id) }
                    continue
                }
                guard !placed.contains(id), entered.insert(id).inserted else { continue }
                stack.append((id, true))
                for dependency in dependencies[id, default: []].reversed() where !placed.contains(dependency) {
                    stack.append((dependency, false))
                }
            }
        }
        return result
    }

    /// `ids` plus every definition they contain, directly or indirectly.
    /// Unknown identifiers are kept; safe on cyclic graphs.
    func dependencyClosure(of ids: Set<PageID>) -> Set<PageID> {
        var result = ids, pending = Array(ids)
        while let next = pending.popLast() {
            for dependency in dependencies[next, default: []] where result.insert(dependency).inserted {
                pending.append(dependency)
            }
        }
        return result
    }

    /// True when an instance of `inner` placed inside `outer` would make
    /// `outer` contain itself.
    func wouldCreateCycle(placing inner: PageID, inside outer: PageID) -> Bool {
        inner == outer || reaches(from: inner, to: outer)
    }

    /// The first rule the graph breaks, checked in a fixed order: cycle, then
    /// depth, then expanded size, each scanning definitions in document order.
    var violation: ComponentGraphViolation? {
        if let cycle { return .init(kind: .cycle, path: cycle, names: cycle.map(name), objectCount: nil) }
        for id in order where (depths[id] ?? 0) > Self.maximumNestingDepth {
            let chain = deepestChain(from: id)
            return .init(kind: .tooDeep, path: chain, names: chain.map(name), objectCount: nil)
        }
        for id in order where (expandedObjects[id] ?? 0) > ResolvedGraphPolicy.maximumNodes {
            return .init(kind: .tooLarge, path: [id], names: [name(id)], objectCount: expandedObjects[id])
        }
        return nil
    }

    private func name(_ id: PageID) -> String { names[id] ?? "Missing component" }

    private func reaches(from start: PageID, to target: PageID) -> Bool {
        var visited = Set<PageID>(), pending = [start]
        while let next = pending.popLast() {
            if next == target { return true }
            guard visited.insert(next).inserted else { continue }
            pending += dependencies[next, default: []]
        }
        return false
    }

    private static func firstCycle(order: [PageID], dependencies: [PageID: [PageID]]) -> [PageID]? {
        enum Mark { case active, done }
        var marks: [PageID: Mark] = [:]
        for start in order where marks[start] == nil {
            var path = [start], cursors = [0]
            marks[start] = .active
            while let current = path.last, let cursor = cursors.last {
                let children = dependencies[current, default: []]
                guard cursor < children.count else {
                    marks[current] = .done
                    path.removeLast(); cursors.removeLast()
                    continue
                }
                cursors[cursors.count - 1] = cursor + 1
                let child = children[cursor]
                switch marks[child] {
                case .active?:
                    guard let start = path.firstIndex(of: child) else { return [child, child] }
                    return Array(path[start...]) + [child]
                case .done?:
                    continue
                case nil:
                    marks[child] = .active
                    path.append(child); cursors.append(0)
                }
            }
        }
        return nil
    }

    /// Post-order over an acyclic graph; never called while a cycle exists.
    private static func measure(order: [PageID], dependencies: [PageID: [PageID]],
                                targets: [PageID: [PageID]], sizes: [PageID: Int])
        -> (depths: [PageID: Int], deepest: [PageID: PageID], objects: [PageID: Int]) {
        let limit = ResolvedGraphPolicy.maximumNodes + 1
        var depths: [PageID: Int] = [:], deepest: [PageID: PageID] = [:], objects: [PageID: Int] = [:]
        for start in order where depths[start] == nil {
            var stack: [(PageID, Bool)] = [(start, false)]
            while let (id, exiting) = stack.popLast() {
                guard depths[id] == nil else { continue }
                let children = dependencies[id, default: []]
                guard exiting else {
                    stack.append((id, true))
                    for child in children.reversed() where depths[child] == nil { stack.append((child, false)) }
                    continue
                }
                var best = 0
                for child in children {
                    let depth = depths[child] ?? 0
                    if depth > best { best = depth; deepest[id] = child }
                }
                depths[id] = best + 1
                var total = min(limit, sizes[id, default: 1])
                for target in targets[id, default: []] {
                    // The instance node is replaced by the definition it resolves to.
                    guard let inner = objects[target] else { continue }
                    total = min(limit, total - 1 + inner)
                }
                objects[id] = total
            }
        }
        return (depths, deepest, objects)
    }
}

/// A broken component-graph rule with the definitions involved, for a
/// specific user-facing message. Diagnostics use `category` and identifiers
/// only; definition names are content and never enter diagnostics.
struct ComponentGraphViolation: Error, Equatable, Sendable, LocalizedError {
    enum Kind: String, Equatable, Sendable {
        case cycle = "component-cycle"
        case tooDeep = "component-nesting-too-deep"
        case tooLarge = "component-expansion-too-large"
    }
    let kind: Kind
    /// Definitions involved, outermost first. A cycle repeats its first
    /// definition at the end.
    let path: [PageID]
    let names: [String]
    let objectCount: Int?

    var category: String { kind.rawValue }

    /// "20,000" whatever the Mac's region, matching the rest of SiteForge's
    /// English-only messages, so the wording and its tests are stable.
    static var objectLimitText: String {
        ResolvedGraphPolicy.maximumNodes.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))
    }

    var errorDescription: String? {
        let chain = names.joined(separator: " → ")
        switch kind {
        case .cycle:
            return "This would place a component inside itself (\(chain)). Remove one of these instances or choose a different component."
        case .tooDeep:
            return "Components can be nested up to \(CanonicalComponentGraph.maximumNestingDepth) levels; \(chain) is \(path.count). Detach an inner instance or shorten the chain."
        case .tooLarge:
            return "“\(names.first ?? "This component")” would expand to more than \(Self.objectLimitText) objects. Use fewer or smaller nested instances."
        }
    }

    var validationError: ModelValidationError {
        switch kind {
        case .cycle: .componentDependencyCycle
        case .tooDeep: .componentNestingTooDeep
        case .tooLarge: .componentExpansionTooLarge
        }
    }
}

enum ComponentTextPropertyIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "component-text-property"
}
typealias ComponentTextPropertyID = StableIdentifier<ComponentTextPropertyIdentifierDomain>

struct ExposedComponentTextProperty: Equatable, Identifiable, Sendable {
    let id: ComponentTextPropertyID
    let sourceNodeID: NodeID
    let label: String
    let defaultValue: String
}

/// SF-0902/0905: definition + property ID is the stable override address.
/// The owning Text node is the binding; content.text is the sole default.
enum CanonicalComponentText {
    static let namespace = "component.exposedText.v1."
    static let overrideNamespace = "component.instance.v1.text."
    static let maximumProperties = 64
    static let maximumTextBytes = 64 * 1_024
    static let metadataKeys = Set([namespace + "id", namespace + "label", namespace + "type"])

    static func validLabel(_ label: String) -> Bool {
        !label.isEmpty && label.utf8.count <= 256
            && label == label.trimmingCharacters(in: .whitespacesAndNewlines)
            && !label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
    static func overrideKey(_ id: ComponentTextPropertyID) -> String { overrideNamespace + id.description }
    static func overrideID(_ key: String) -> ComponentTextPropertyID? {
        guard key.hasPrefix(overrideNamespace) else { return nil }
        let raw = String(key.dropFirst(overrideNamespace.count))
        guard let id = ComponentTextPropertyID(uuidString: raw), id.description == raw else { return nil }
        return id
    }
    static func property(on node: DocumentNode) -> ExposedComponentTextProperty? {
        guard node.kind == .text,
              let raw = node.properties.first(where: { $0.key.rawValue == namespace + "id" }),
              case .string(let identifier) = raw.value, let id = ComponentTextPropertyID(uuidString: identifier),
              let label = node.properties.first(where: { $0.key.rawValue == namespace + "label" }),
              case .string(let labelValue) = label.value,
              let content = node.properties.first(where: { $0.key.rawValue == "content.text" }),
              case .string(let text) = content.value else { return nil }
        return .init(id: id, sourceNodeID: node.id, label: labelValue, defaultValue: text)
    }
    static func properties(in definition: DocumentPage) -> [ExposedComponentTextProperty] {
        definition.nodes.compactMap(property)
    }
    static func overrides(on instance: DocumentNode) -> [ComponentTextPropertyID: String] {
        var result: [ComponentTextPropertyID: String] = [:]
        for property in instance.properties {
            if let id = overrideID(property.key.rawValue), case .string(let text) = property.value { result[id] = text }
        }
        return result
    }
    static func unresolvedOverrides(on instance: DocumentNode, definition: DocumentPage) -> Set<ComponentTextPropertyID> {
        Set(overrides(on: instance).keys).subtracting(properties(in: definition).map(\.id))
    }
    static func validate(_ node: DocumentNode, inDefinition: Bool) throws {
        guard node.properties.filter({ $0.key.rawValue.hasPrefix(overrideNamespace) }).count <= maximumProperties else {
            throw ModelValidationError.invalidComponentReference
        }
        let metadata = node.properties.filter { $0.key.rawValue.hasPrefix(namespace) }
        if !metadata.isEmpty {
            guard inDefinition, node.kind == .text,
                  Set(metadata.map(\.key.rawValue)) == metadataKeys,
                  metadata.allSatisfy({ $0.origin == .authored }),
                  let property = property(on: node), validLabel(property.label),
                  property.defaultValue.utf8.count <= maximumTextBytes,
                  node.properties.first(where: { $0.key.rawValue == namespace + "id" })?.value == .string(property.id.description),
                  node.properties.first(where: { $0.key.rawValue == namespace + "type" })?.value == .string("plain-text") else {
                throw ModelValidationError.invalidComponentReference
            }
        }
        // OD-034: an instance inside a definition owns values for its own
        // definition's properties exactly like an instance on a page.
        for property in node.properties where property.key.rawValue.hasPrefix(overrideNamespace) {
            guard node.kind == .component,
                  overrideID(property.key.rawValue) != nil, property.origin == .authored,
                  case .string(let text) = property.value, text.utf8.count <= maximumTextBytes else {
                throw ModelValidationError.invalidComponentReference
            }
        }
    }
    /// Compare complete transaction results, not intermediate remove/insert
    /// commands. Explicit detach/reset may resolve intent; raw source deletion
    /// may not silently strand a previously valid authored override.
    static func validateTransition(from old: CanonicalDocument, to new: CanonicalDocument) throws {
        let oldDefinitions = Dictionary(uniqueKeysWithValues: old.componentDefinitions.map { ($0.id, $0) })
        let newDefinitions = Dictionary(uniqueKeysWithValues: new.componentDefinitions.map { ($0.id, $0) })
        let newNodes = Dictionary(uniqueKeysWithValues: new.pages.flatMap(\.nodes).map { ($0.id, $0) })
        for instance in old.pages.flatMap(\.nodes) {
            guard let definitionID = CanonicalComponentReference.definitionID(for: instance),
                  let oldDefinition = oldDefinitions[definitionID],
                  let newInstance = newNodes[instance.id], newInstance.kind == .component else { continue }
            let retained = Set(overrides(on: instance).keys).intersection(overrides(on: newInstance).keys)
            guard retained.isEmpty || CanonicalComponentReference.definitionID(for: newInstance) == definitionID else {
                throw ModelValidationError.componentTextIntentWouldBeLost
            }
            let prior = Dictionary(uniqueKeysWithValues: properties(in: oldDefinition).map { ($0.id, $0.sourceNodeID) })
            let current = Dictionary(uniqueKeysWithValues: (newDefinitions[definitionID].map(properties) ?? []).map { ($0.id, $0.sourceNodeID) })
            for id in overrides(on: instance).keys where prior[id] != nil && overrides(on: newInstance)[id] != nil {
                // Removing an exposed binding deliberately leaves the authored
                // instance value as an explicit, resettable conflict. Reusing
                // the same stable property ID for a different source is still
                // rejected because that would silently retarget intent.
                if let newSource = current[id], newSource != prior[id] {
                    throw ModelValidationError.componentTextIntentWouldBeLost
                }
            }
        }
    }
}

enum ComponentVisibilityPropertyIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "component-visibility-property"
}

enum ComponentChoicePropertyIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "component-choice-property"
}
typealias ComponentChoicePropertyID = StableIdentifier<ComponentChoicePropertyIdentifierDomain>

struct ExposedComponentChoiceProperty: Equatable, Identifiable, Sendable {
    let id: ComponentChoicePropertyID
    let sourceNodeID: NodeID
    let label: String
    let defaultValue: ImageFitMode
}

/// SF-0902: the first bounded enum binding exposes an Image node's canonical
/// fit mode. The definition's image property remains the sole default and the
/// instance stores only a typed stable-property override.
enum CanonicalComponentChoice {
    static let namespace = "component.exposedChoice.v1."
    static let overrideNamespace = "component.instance.v1.choice."
    static let metadataKeys = Set([namespace + "id", namespace + "label", namespace + "type"])
    static let maximumProperties = 64

    static func overrideKey(_ id: ComponentChoicePropertyID) -> String { overrideNamespace + id.description }
    static func overrideID(_ key: String) -> ComponentChoicePropertyID? {
        guard key.hasPrefix(overrideNamespace) else { return nil }
        let raw = String(key.dropFirst(overrideNamespace.count))
        guard let id = ComponentChoicePropertyID(uuidString: raw), id.description == raw else { return nil }
        return id
    }
    static func property(on node: DocumentNode) -> ExposedComponentChoiceProperty? {
        guard node.kind == .image,
              let raw = node.insertionStringProperty(namespace + "id"),
              let id = ComponentChoicePropertyID(uuidString: raw), id.description == raw,
              let label = node.insertionStringProperty(namespace + "label"),
              CanonicalComponentText.validLabel(label),
              node.insertionStringProperty(namespace + "type") == "image-fit",
              let rawDefault = node.insertionStringProperty(CanonicalImageStyle.namespace + "fit"),
              let value = ImageFitMode(rawValue: rawDefault) else { return nil }
        return .init(id: id, sourceNodeID: node.id, label: label, defaultValue: value)
    }
    static func properties(in definition: DocumentPage) -> [ExposedComponentChoiceProperty] {
        definition.nodes.compactMap(property)
    }
    static func overrides(on instance: DocumentNode) -> [ComponentChoicePropertyID: ImageFitMode] {
        Dictionary(uniqueKeysWithValues: instance.properties.compactMap { property in
            guard let id = overrideID(property.key.rawValue), case .string(let raw) = property.value,
                  let value = ImageFitMode(rawValue: raw) else { return nil }
            return (id, value)
        })
    }
    static func validate(_ node: DocumentNode, inDefinition: Bool) throws {
        let metadata = node.properties.filter { $0.key.rawValue.hasPrefix(namespace) }
        if !metadata.isEmpty {
            guard inDefinition, node.kind == .image,
                  Set(metadata.map(\.key.rawValue)) == metadataKeys,
                  metadata.allSatisfy({ $0.origin == .authored }), property(on: node) != nil else {
                throw ModelValidationError.invalidComponentReference
            }
        }
        let overrides = node.properties.filter { $0.key.rawValue.hasPrefix(overrideNamespace) }
        guard overrides.count <= maximumProperties else { throw ModelValidationError.invalidComponentReference }
        for property in overrides {
            guard node.kind == .component, overrideID(property.key.rawValue) != nil,
                  property.origin == .authored, case .string(let raw) = property.value,
                  ImageFitMode(rawValue: raw) != nil else { throw ModelValidationError.invalidComponentReference }
        }
    }
    static func validateTransition(from old: CanonicalDocument, to new: CanonicalDocument) throws {
        let oldDefinitions = Dictionary(uniqueKeysWithValues: old.componentDefinitions.map { ($0.id, $0) })
        let newDefinitions = Dictionary(uniqueKeysWithValues: new.componentDefinitions.map { ($0.id, $0) })
        let newNodes = Dictionary(uniqueKeysWithValues: new.pages.flatMap(\.nodes).map { ($0.id, $0) })
        for instance in old.pages.flatMap(\.nodes) {
            guard let definitionID = CanonicalComponentReference.definitionID(for: instance),
                  let oldDefinition = oldDefinitions[definitionID],
                  let newInstance = newNodes[instance.id], newInstance.kind == .component else { continue }
            let retained = Set(overrides(on: instance).keys).intersection(overrides(on: newInstance).keys)
            guard retained.isEmpty || CanonicalComponentReference.definitionID(for: newInstance) == definitionID else {
                throw ModelValidationError.invalidComponentReference
            }
            let prior = Dictionary(uniqueKeysWithValues: properties(in: oldDefinition).map { ($0.id, $0.sourceNodeID) })
            let current = Dictionary(uniqueKeysWithValues: (newDefinitions[definitionID].map(properties) ?? []).map { ($0.id, $0.sourceNodeID) })
            for id in retained where prior[id] != nil {
                if let source = current[id], source != prior[id] { throw ModelValidationError.invalidComponentReference }
            }
        }
    }
}

enum ComponentMediaPropertyIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "component-media-property"
}
typealias ComponentMediaPropertyID = StableIdentifier<ComponentMediaPropertyIdentifierDomain>

struct ExposedComponentMediaProperty: Equatable, Identifiable, Sendable {
    let id: ComponentMediaPropertyID
    let sourceNodeID: NodeID
    let label: String
    let defaultValue: AssetID
}

/// SF-0902: a bounded media binding exposes an Image node's canonical local
/// AssetID. Instances store only the stable asset reference; bytes remain in
/// the project resource store and the definition remains the default source.
enum CanonicalComponentMedia {
    static let namespace = "component.exposedMedia.v1."
    static let overrideNamespace = "component.instance.v1.media."
    static let metadataKeys = Set([namespace + "id", namespace + "label", namespace + "type"])
    static let maximumProperties = 64

    static func overrideKey(_ id: ComponentMediaPropertyID) -> String { overrideNamespace + id.description }
    static func overrideID(_ key: String) -> ComponentMediaPropertyID? {
        guard key.hasPrefix(overrideNamespace) else { return nil }
        let raw = String(key.dropFirst(overrideNamespace.count))
        guard let id = ComponentMediaPropertyID(uuidString: raw), id.description == raw else { return nil }
        return id
    }
    static func property(on node: DocumentNode) -> ExposedComponentMediaProperty? {
        guard node.kind == .image,
              let raw = node.insertionStringProperty(namespace + "id"),
              let id = ComponentMediaPropertyID(uuidString: raw), id.description == raw,
              let label = node.insertionStringProperty(namespace + "label"),
              CanonicalComponentText.validLabel(label),
              node.insertionStringProperty(namespace + "type") == "image-asset",
              let assetRaw = node.insertionStringProperty(CanonicalImageStyle.namespace + "assetID"),
              let assetID = AssetID(uuidString: assetRaw), assetID.description == assetRaw else { return nil }
        return .init(id: id, sourceNodeID: node.id, label: label, defaultValue: assetID)
    }
    static func properties(in definition: DocumentPage) -> [ExposedComponentMediaProperty] {
        definition.nodes.compactMap(property)
    }
    static func overrides(on instance: DocumentNode) -> [ComponentMediaPropertyID: AssetID] {
        Dictionary(uniqueKeysWithValues: instance.properties.compactMap { property in
            guard let id = overrideID(property.key.rawValue), case .string(let raw) = property.value,
                  let value = AssetID(uuidString: raw), value.description == raw else { return nil }
            return (id, value)
        })
    }
    static func validate(_ node: DocumentNode, inDefinition: Bool) throws {
        let metadata = node.properties.filter { $0.key.rawValue.hasPrefix(namespace) }
        if !metadata.isEmpty {
            guard inDefinition, node.kind == .image,
                  Set(metadata.map(\.key.rawValue)) == metadataKeys,
                  metadata.allSatisfy({ $0.origin == .authored }), property(on: node) != nil else {
                throw ModelValidationError.invalidComponentReference
            }
        }
        let overrides = node.properties.filter { $0.key.rawValue.hasPrefix(overrideNamespace) }
        guard overrides.count <= maximumProperties else { throw ModelValidationError.invalidComponentReference }
        for property in overrides {
            guard node.kind == .component, overrideID(property.key.rawValue) != nil,
                  property.origin == .authored, case .string(let raw) = property.value,
                  let assetID = AssetID(uuidString: raw), assetID.description == raw else {
                throw ModelValidationError.invalidComponentReference
            }
        }
    }
    static func validateTransition(from old: CanonicalDocument, to new: CanonicalDocument) throws {
        let oldDefinitions = Dictionary(uniqueKeysWithValues: old.componentDefinitions.map { ($0.id, $0) })
        let newDefinitions = Dictionary(uniqueKeysWithValues: new.componentDefinitions.map { ($0.id, $0) })
        let newNodes = Dictionary(uniqueKeysWithValues: new.pages.flatMap(\.nodes).map { ($0.id, $0) })
        for instance in old.pages.flatMap(\.nodes) {
            guard let definitionID = CanonicalComponentReference.definitionID(for: instance),
                  let oldDefinition = oldDefinitions[definitionID],
                  let newInstance = newNodes[instance.id], newInstance.kind == .component else { continue }
            let retained = Set(overrides(on: instance).keys).intersection(overrides(on: newInstance).keys)
            guard retained.isEmpty || CanonicalComponentReference.definitionID(for: newInstance) == definitionID else {
                throw ModelValidationError.invalidComponentReference
            }
            let prior = Dictionary(uniqueKeysWithValues: properties(in: oldDefinition).map { ($0.id, $0.sourceNodeID) })
            let current = Dictionary(uniqueKeysWithValues: (newDefinitions[definitionID].map(properties) ?? []).map { ($0.id, $0.sourceNodeID) })
            for id in retained where prior[id] != nil {
                if let source = current[id], source != prior[id] { throw ModelValidationError.invalidComponentReference }
            }
        }
    }
}

enum ComponentActionPropertyIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "component-action-property"
}
typealias ComponentActionPropertyID = StableIdentifier<ComponentActionPropertyIdentifierDomain>

struct ExposedComponentActionProperty: Equatable, Identifiable, Sendable {
    let id: ComponentActionPropertyID
    let sourceNodeID: NodeID
    let label: String
    let defaultValue: CanonicalLinkTarget
}

/// SF-0902/SF-0905: an action binding exposes a Button or Link destination.
/// The compact value codec is canonical and path-free; instance values retain
/// stable page/node identities or the validated external URL intent.
enum CanonicalComponentAction {
    static let namespace = "component.exposedAction.v1."
    static let overrideNamespace = "component.instance.v1.action."
    static let metadataKeys = Set([namespace + "id", namespace + "label", namespace + "type"])
    static let maximumProperties = 64

    static func overrideKey(_ id: ComponentActionPropertyID) -> String { overrideNamespace + id.description }
    static func overrideID(_ key: String) -> ComponentActionPropertyID? {
        guard key.hasPrefix(overrideNamespace) else { return nil }
        let raw = String(key.dropFirst(overrideNamespace.count))
        guard let id = ComponentActionPropertyID(uuidString: raw), id.description == raw else { return nil }
        return id
    }
    static func encode(_ target: CanonicalLinkTarget) -> String {
        switch target {
        case .none: return "none"
        case .page(let pageID): return "page:\(pageID.description)"
        case .section(let pageID, let nodeID): return "section:\(pageID.description):\(nodeID.description)"
        case .external(let value): return "external:\(Data(value.utf8).base64EncodedString())"
        }
    }
    static func decode(_ raw: String) -> CanonicalLinkTarget? {
        guard raw.utf8.count <= 11_000 else { return nil }
        if raw == "none" { return CanonicalLinkTarget.none }
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2, parts[0] == "page", let id = PageID(uuidString: String(parts[1])), id.description == parts[1] {
            return .page(id)
        }
        if parts.count == 3, parts[0] == "section",
           let pageID = PageID(uuidString: String(parts[1])), pageID.description == parts[1],
           let nodeID = NodeID(uuidString: String(parts[2])), nodeID.description == parts[2] {
            return .section(pageID: pageID, nodeID: nodeID)
        }
        if parts.count == 2, parts[0] == "external", let data = Data(base64Encoded: String(parts[1])),
           data.base64EncodedString() == parts[1], let value = String(data: data, encoding: .utf8),
           CanonicalLinkTarget.validateExternal(value) { return .external(value) }
        return nil
    }
    static func property(on node: DocumentNode) -> ExposedComponentActionProperty? {
        guard node.kind.isLinkControl,
              let raw = node.insertionStringProperty(namespace + "id"),
              let id = ComponentActionPropertyID(uuidString: raw), id.description == raw,
              let label = node.insertionStringProperty(namespace + "label"), CanonicalComponentText.validLabel(label),
              node.insertionStringProperty(namespace + "type") == "link-target",
              let value = try? CanonicalLinkTarget.resolve(node) else { return nil }
        return .init(id: id, sourceNodeID: node.id, label: label, defaultValue: value)
    }
    static func properties(in definition: DocumentPage) -> [ExposedComponentActionProperty] { definition.nodes.compactMap(property) }
    static func overrides(on instance: DocumentNode) -> [ComponentActionPropertyID: CanonicalLinkTarget] {
        Dictionary(uniqueKeysWithValues: instance.properties.compactMap { property in
            guard let id = overrideID(property.key.rawValue), case .string(let raw) = property.value,
                  let value = decode(raw) else { return nil }
            return (id, value)
        })
    }
    static func validate(_ node: DocumentNode, inDefinition: Bool) throws {
        let metadata = node.properties.filter { $0.key.rawValue.hasPrefix(namespace) }
        if !metadata.isEmpty {
            guard inDefinition, node.kind.isLinkControl, Set(metadata.map(\.key.rawValue)) == metadataKeys,
                  metadata.allSatisfy({ $0.origin == .authored }), property(on: node) != nil else {
                throw ModelValidationError.invalidComponentReference
            }
        }
        let overrides = node.properties.filter { $0.key.rawValue.hasPrefix(overrideNamespace) }
        guard overrides.count <= maximumProperties else { throw ModelValidationError.invalidComponentReference }
        for property in overrides {
            guard node.kind == .component, overrideID(property.key.rawValue) != nil,
                  property.origin == .authored, case .string(let raw) = property.value, decode(raw) != nil else {
                throw ModelValidationError.invalidComponentReference
            }
        }
    }
    static func validateTransition(from old: CanonicalDocument, to new: CanonicalDocument) throws {
        let definitions = Dictionary(uniqueKeysWithValues: new.componentDefinitions.map { ($0.id, $0) })
        let instances = Dictionary(uniqueKeysWithValues: new.pages.flatMap(\.nodes).map { ($0.id, $0) })
        for oldInstance in old.pages.flatMap(\.nodes) {
            guard let definitionID = CanonicalComponentReference.definitionID(for: oldInstance),
                  let oldDefinition = old.componentDefinitions.first(where: { $0.id == definitionID }),
                  let instance = instances[oldInstance.id], instance.kind == .component else { continue }
            let retained = Set(overrides(on: oldInstance).keys).intersection(overrides(on: instance).keys)
            guard retained.isEmpty || CanonicalComponentReference.definitionID(for: instance) == definitionID else {
                throw ModelValidationError.invalidComponentReference
            }
            let previous = Dictionary(uniqueKeysWithValues: properties(in: oldDefinition).map { ($0.id, $0.sourceNodeID) })
            let current = Dictionary(uniqueKeysWithValues: (definitions[definitionID].map(properties) ?? []).map { ($0.id, $0.sourceNodeID) })
            for id in retained where previous[id] != nil {
                if let source = current[id], source != previous[id] { throw ModelValidationError.invalidComponentReference }
            }
        }
    }
}
enum ComponentSlotPropertyIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "component-slot-property"
}
typealias ComponentSlotPropertyID = StableIdentifier<ComponentSlotPropertyIdentifierDomain>

struct ExposedComponentSlotProperty: Equatable, Identifiable, Sendable {
    let id: ComponentSlotPropertyID
    let sourceNodeID: NodeID
    let label: String
    /// Sole fallback ownership stays in the definition's ordered child graph.
    let defaultChildIDs: [NodeID]
    /// OD-018 (schema 25): optional authored constraints on top-level content.
    var rules: CanonicalSlotRules = .unrestricted
}

/// OD-018 / SF-0903 (document schema 25): optional authored constraints for a
/// slot's top-level content. They apply to the definition's default contents
/// and to every instance's supplied contents; a document that breaks them is
/// invalid, so every editing path enforces them through the command kernel.
struct CanonicalSlotRules: Equatable, Hashable, Sendable {
    /// nil = any supported kind.
    let allowedKinds: Set<NodeKind>?
    /// nil = up to `CanonicalComponentSlot.maximumRoots`.
    let maximumRoots: Int?

    /// No authored constraints. (Not named `none`, which would be read as
    /// `Optional.none` wherever a value is optional.)
    static let unrestricted = CanonicalSlotRules(allowedKinds: nil, maximumRoots: nil)

    init(allowedKinds: Set<NodeKind>?, maximumRoots: Int?) {
        self.allowedKinds = allowedKinds
        self.maximumRoots = maximumRoots
    }

    var isEmpty: Bool { allowedKinds == nil && maximumRoots == nil }

    /// Canonical encodings: kinds in `CanonicalComponentSlot.allowedRootKinds`
    /// order, comma-separated, at least one; maximum a whole number 1…256.
    var encodedKinds: String? {
        allowedKinds.map { kinds in CanonicalComponentSlot.allowedRootKinds.filter(kinds.contains).map(\.rawValue).joined(separator: ",") }
    }

    var isValid: Bool {
        if let allowedKinds {
            guard !allowedKinds.isEmpty, allowedKinds.isSubset(of: Set(CanonicalComponentSlot.allowedRootKinds)) else { return false }
        }
        if let maximumRoots { guard (1...CanonicalComponentSlot.maximumRoots).contains(maximumRoots) else { return false } }
        return true
    }

    static func decode(kinds: PropertyValue?, maximum: PropertyValue?) -> CanonicalSlotRules? {
        var allowed: Set<NodeKind>?
        if let kinds {
            guard case .string(let raw) = kinds else { return nil }
            let parts = raw.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            let parsed = parts.compactMap(NodeKind.init(rawValue:))
            guard !parts.isEmpty, parsed.count == parts.count, Set(parsed).count == parsed.count else { return nil }
            allowed = Set(parsed)
        }
        var maximumRoots: Int?
        if let maximum {
            guard case .number(let value) = maximum, value.isFinite, value.rounded() == value,
                  value >= 1, value <= Double(CanonicalComponentSlot.maximumRoots) else { return nil }
            maximumRoots = Int(value)
        }
        let rules = CanonicalSlotRules(allowedKinds: allowed, maximumRoots: maximumRoots)
        guard rules.isValid else { return nil }
        // One canonical spelling: the same kinds in a different order are not accepted.
        if case .string(let raw)? = kinds, rules.encodedKinds != raw { return nil }
        return rules
    }

    /// The first rule `roots` (top-level content, in order) breaks, or nil.
    func violation(for roots: [DocumentNode]) -> CanonicalSlotRuleViolation? {
        if let allowedKinds, let offending = roots.first(where: { !allowedKinds.contains($0.kind) }) {
            return .kind(offending.kind, allowed: CanonicalComponentSlot.allowedRootKinds.filter(allowedKinds.contains))
        }
        if let maximumRoots, roots.count > maximumRoots { return .count(roots.count, maximum: maximumRoots) }
        return nil
    }
}

enum CanonicalSlotRuleViolation: Equatable, Sendable {
    case kind(NodeKind, allowed: [NodeKind])
    case count(Int, maximum: Int)

    static func title(_ kind: NodeKind) -> String {
        switch kind {
        case .frame: "Frame"
        case .text: "Text"
        case .section: "Section"
        case .stack: "Stack"
        case .grid: "Grid"
        case .image: "Image"
        case .button: "Button"
        case .link: "Link"
        case .form: "Form"
        case .component: "Component"
        }
    }

    /// The broken rule in words, without content values.
    var summary: String {
        switch self {
        case .kind(let kind, let allowed):
            "\(Self.title(kind)) is not allowed; this slot accepts \(allowed.map(Self.title).joined(separator: ", "))"
        case .count(let count, let maximum):
            "\(count) items is more than this slot's limit of \(maximum)"
        }
    }
}

/// Where a slot's projected content comes from on one instance (SF-0903-001/003).
enum CanonicalSlotState: Equatable, Sendable {
    /// Nothing stored on the instance: the definition's default contents.
    case inherited
    /// Authored empty: shows nothing, distinct from inheritance.
    case empty
    /// The instance owns these ordered top-level roots.
    case supplied([NodeID])
}

/// SF-0903 named slots. Fallback content is the definition container's own
/// ordered children. OD-018 (schema 25) adds instance-owned supplied content:
/// the instance stores `component.instance.v1.slot.<slot>` = "supplied" or
/// "empty" (absent = inherit); supplied top-level roots are the instance's own
/// canonical children, each marked with `component.supplied.v1.slotID`, in
/// childIDs order. The definition never owns instance content. Supplied
/// geometry is slot-local (offset from the slot container's origin).
enum CanonicalComponentSlot {
    static let namespace = "component.exposedSlot.v1."
    static let overrideNamespace = "component.instance.v1.slot."
    /// Earlier name of `overrideNamespace`, from when it was reserved only.
    static let unsupportedOverrideNamespace = overrideNamespace
    static let supplyKey = "component.supplied.v1.slotID"
    static let metadataKeys = Set([namespace + "id", namespace + "label", namespace + "type"])
    static let allowedKindsKey = namespace + "allowedKinds"
    static let maximumRootsKey = namespace + "maximumRoots"
    static let ruleKeys = Set([allowedKindsKey, maximumRootsKey])
    static let supportedKinds: Set<NodeKind> = [.frame, .section, .stack, .grid]
    /// Supplied content, the empty state and slot rules need schema 25.
    static let contentSchema = 25
    /// Upper bound on top-level items in one slot (SF-0903-007).
    static let maximumRoots = 256
    static let allowedRootKinds: [NodeKind] = [.frame, .text, .section, .stack, .grid, .image, .button, .link, .form, .component]
    static let suppliedValue = "supplied"
    static let emptyValue = "empty"

    static func property(on node: DocumentNode) -> ExposedComponentSlotProperty? {
        guard supportedKinds.contains(node.kind),
              let raw = node.insertionStringProperty(namespace + "id"),
              let id = ComponentSlotPropertyID(uuidString: raw), id.description == raw,
              let label = node.insertionStringProperty(namespace + "label"), CanonicalComponentText.validLabel(label),
              node.insertionStringProperty(namespace + "type") == "ordered-fallback-children",
              let rules = CanonicalSlotRules.decode(kinds: node.insertionProperty(allowedKindsKey)?.value,
                                                    maximum: node.insertionProperty(maximumRootsKey)?.value) else { return nil }
        return .init(id: id, sourceNodeID: node.id, label: label, defaultChildIDs: node.childIDs, rules: rules)
    }
    static func properties(in definition: DocumentPage) -> [ExposedComponentSlotProperty] {
        definition.nodes.compactMap(property)
    }
    static func validate(_ node: DocumentNode, inDefinition: Bool) throws {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix(namespace) }
        guard !owned.isEmpty else { return }
        let keys = Set(owned.map(\.key.rawValue))
        guard inDefinition, metadataKeys.isSubset(of: keys), keys.isSubset(of: metadataKeys.union(ruleKeys)),
              owned.count == keys.count, owned.allSatisfy({ $0.origin == .authored }),
              property(on: node) != nil else { throw ModelValidationError.invalidComponentReference }
    }

    // MARK: Instance state (OD-018)

    static func overrideKey(_ id: ComponentSlotPropertyID) -> String { overrideNamespace + id.description }
    static func overrideID(_ key: String) -> ComponentSlotPropertyID? {
        guard key.hasPrefix(overrideNamespace) else { return nil }
        let raw = String(key.dropFirst(overrideNamespace.count))
        guard let id = ComponentSlotPropertyID(uuidString: raw), id.description == raw else { return nil }
        return id
    }
    /// The instance's per-slot markers ("supplied" / "empty"), by slot.
    static func markers(on instance: DocumentNode) -> [ComponentSlotPropertyID: NodeProperty] {
        var result: [ComponentSlotPropertyID: NodeProperty] = [:]
        for property in instance.properties {
            if let id = overrideID(property.key.rawValue) { result[id] = property }
        }
        return result
    }
    /// The slot a supplied top-level root belongs to.
    static func suppliedSlotID(_ node: DocumentNode) -> ComponentSlotPropertyID? {
        node.insertionStringProperty(supplyKey).flatMap(ComponentSlotPropertyID.init(uuidString:))
    }
    /// Supplied roots of `instance` grouped by slot, each in childIDs order.
    static func suppliedRoots(of instance: DocumentNode,
                              nodesByID: [NodeID: DocumentNode]) -> [ComponentSlotPropertyID: [DocumentNode]] {
        var result: [ComponentSlotPropertyID: [DocumentNode]] = [:]
        for id in instance.childIDs {
            guard let node = nodesByID[id], let slot = suppliedSlotID(node) else { continue }
            result[slot, default: []].append(node)
        }
        return result
    }
    static func state(of slot: ComponentSlotPropertyID, on instance: DocumentNode,
                      nodesByID: [NodeID: DocumentNode]) -> CanonicalSlotState {
        switch markers(on: instance)[slot]?.value {
        case .string(emptyValue)?: return .empty
        case .string(suppliedValue)?: return .supplied(suppliedRoots(of: instance, nodesByID: nodesByID)[slot]?.map(\.id) ?? [])
        default: return .inherited
        }
    }
    /// Every node inside instance-owned supplied content on `page`.
    static func suppliedNodeIDs(in page: DocumentPage) -> Set<NodeID> {
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        var result = Set<NodeID>()
        var pending = page.nodes.filter { $0.kind == .component }.flatMap(\.childIDs)
        while let id = pending.popLast() {
            guard result.insert(id).inserted, let node = byID[id] else { continue }
            pending += node.childIDs
        }
        return result
    }

    /// Document-level rules for supplied content and slot rules: membership
    /// keys only on an instance's direct children; one consistent marker per
    /// supplied slot; "empty" with no roots; bounded counts; definitions'
    /// default contents and existing slots' supplied contents obey the rules.
    /// A slot or definition that no longer exists keeps its content as a
    /// conflict (`CanonicalComponentOverrides`), not an invalid document.
    static func validateContent(in document: CanonicalDocument) throws {
        let slotsByDefinition = Self.slotsByDefinition(document.componentDefinitions)
        for definition in document.componentDefinitions {
            let byID = Dictionary(uniqueKeysWithValues: definition.nodes.map { ($0.id, $0) })
            for slot in slotsByDefinition[definition.id, default: [:]].values
            where slot.rules.violation(for: slot.defaultChildIDs.compactMap { byID[$0] }) != nil {
                throw ModelValidationError.componentSlotRuleBroken
            }
        }
        for page in document.pages {
            try validateNodes(page.nodes, inDefinition: page.role == .componentDefinition, slotsByDefinition: slotsByDefinition)
        }
    }

    static func slotsByDefinition(_ definitions: [DocumentPage]) -> [PageID: [ComponentSlotPropertyID: ExposedComponentSlotProperty]] {
        var result: [PageID: [ComponentSlotPropertyID: ExposedComponentSlotProperty]] = [:]
        for definition in definitions where definition.role == .componentDefinition {
            result[definition.id] = Dictionary(properties(in: definition).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        return result
    }

    /// One graph's supplied-content rules (a page, a definition, or the nodes
    /// of a clipboard envelope); see `validateContent`.
    static func validateNodes(_ nodes: [DocumentNode], inDefinition: Bool,
                              slotsByDefinition: [PageID: [ComponentSlotPropertyID: ExposedComponentSlotProperty]]) throws {
        let byID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var supplied = Set<NodeID>()
        if inDefinition {
            var pending = nodes.filter { $0.kind == .component }.flatMap(\.childIDs)
            while let id = pending.popLast() {
                guard supplied.insert(id).inserted, let node = byID[id] else { continue }
                pending += node.childIDs
            }
        }
        for node in nodes {
            if node.insertionProperty(supplyKey) != nil {
                guard case .node(let parentID) = node.parent, byID[parentID]?.kind == .component,
                      let property = node.insertionProperty(supplyKey), property.origin == .authored,
                      case .string(let raw) = property.value,
                      let id = ComponentSlotPropertyID(uuidString: raw), id.description == raw else {
                    throw ModelValidationError.invalidComponentReference
                }
            }
            // Inside a definition, supplied content of a nested instance is
            // the instance's, not a source of the definition's own bindings.
            if supplied.contains(node.id), node.properties.contains(where: { property in
                let key = property.key.rawValue
                return key.hasPrefix(CanonicalComponentText.namespace) || key.hasPrefix(CanonicalComponentVisibility.namespace)
                    || key.hasPrefix(CanonicalComponentChoice.namespace) || key.hasPrefix(CanonicalComponentMedia.namespace)
                    || key.hasPrefix(CanonicalComponentAction.namespace) || key.hasPrefix(namespace)
                    || key.hasPrefix(CanonicalComponentOrganization.namespace)
            }) { throw ModelValidationError.invalidComponentReference }
            guard node.kind == .component else { continue }
            let slotMarkers = Self.markers(on: node)
            let roots = suppliedRoots(of: node, nodesByID: byID)
            guard node.childIDs.allSatisfy({ byID[$0].flatMap(suppliedSlotID) != nil }),
                  slotMarkers.count <= CanonicalComponentText.maximumProperties else {
                throw ModelValidationError.invalidComponentReference
            }
            for (slot, marker) in slotMarkers {
                guard marker.origin == .authored, case .string(let value) = marker.value else {
                    throw ModelValidationError.invalidComponentReference
                }
                switch value {
                case suppliedValue: guard let items = roots[slot], !items.isEmpty, items.count <= maximumRoots else {
                    throw ModelValidationError.invalidComponentReference
                }
                case emptyValue: guard roots[slot] == nil else { throw ModelValidationError.invalidComponentReference }
                default: throw ModelValidationError.invalidComponentReference
                }
            }
            let suppliedSlots = Set(slotMarkers.filter { $0.value.value == .string(suppliedValue) }.keys)
            guard Set(roots.keys).isSubset(of: suppliedSlots) else {
                throw ModelValidationError.invalidComponentReference
            }
            if let definitionID = CanonicalComponentReference.definitionID(for: node),
               let slots = slotsByDefinition[definitionID] {
                for (slot, items) in roots {
                    if let exposed = slots[slot], exposed.rules.violation(for: items) != nil {
                        throw ModelValidationError.componentSlotRuleBroken
                    }
                }
            }
        }
    }

    /// The rule a definition's default contents or any instance's supplied
    /// contents would break under `rules`, with how many copies, for a
    /// specific refusal message before committing a rule change.
    static func ruleConflicts(_ rules: CanonicalSlotRules, slot: ExposedComponentSlotProperty,
                              definitionID: PageID, in document: CanonicalDocument)
        -> (defaults: CanonicalSlotRuleViolation?, copies: Int, firstCopy: CanonicalSlotRuleViolation?) {
        var defaults: CanonicalSlotRuleViolation?
        if let definition = document.componentDefinitions.first(where: { $0.id == definitionID }) {
            let byID = Dictionary(uniqueKeysWithValues: definition.nodes.map { ($0.id, $0) })
            defaults = rules.violation(for: slot.defaultChildIDs.compactMap { byID[$0] })
        }
        var copies = 0, first: CanonicalSlotRuleViolation?
        for page in document.pages {
            let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
            for instance in page.nodes where CanonicalComponentReference.definitionID(for: instance) == definitionID {
                guard let items = suppliedRoots(of: instance, nodesByID: byID)[slot.id],
                      let violation = rules.violation(for: items) else { continue }
                copies += 1
                if first == nil { first = violation }
            }
        }
        return (defaults, copies, first)
    }

    static func validateTransition(from old: CanonicalDocument, to new: CanonicalDocument) throws {
        let newInstances = Dictionary(uniqueKeysWithValues: new.pages.flatMap(\.nodes).map { ($0.id, $0) })
        let liveDefinitionIDs = Set(old.pages.flatMap(\.nodes).compactMap { node -> PageID? in
            guard let definitionID = CanonicalComponentReference.definitionID(for: node),
                  let retained = newInstances[node.id],
                  CanonicalComponentReference.definitionID(for: retained) == definitionID else { return nil }
            return definitionID
        })
        for previous in old.componentDefinitions where liveDefinitionIDs.contains(previous.id) {
            guard let current = new.componentDefinitions.first(where: { $0.id == previous.id }) else { continue }
            let bindings = Dictionary(uniqueKeysWithValues: properties(in: current).map { ($0.id, $0.sourceNodeID) })
            for binding in properties(in: previous) {
                if let source = bindings[binding.id], source != binding.sourceNodeID {
                    throw ModelValidationError.invalidComponentReference
                }
            }
        }
        // OD-018: an instance that keeps slot state keeps its definition.
        for instance in old.pages.flatMap(\.nodes) where !markers(on: instance).isEmpty {
            guard let retained = newInstances[instance.id], !markers(on: retained).isEmpty else { continue }
            guard CanonicalComponentReference.definitionID(for: retained) == CanonicalComponentReference.definitionID(for: instance) else {
                throw ModelValidationError.componentSlotContentWouldBeLost
            }
        }
    }
    static func validateDefinition(_ definition: DocumentPage) throws {
        let slots = properties(in: definition)
        let byID = Dictionary(uniqueKeysWithValues: definition.nodes.map { ($0.id, $0) })
        let slotNodeIDs = Set(slots.map(\.sourceNodeID))
        guard Set(slots.map(\.id)).count == slots.count,
              slots.allSatisfy({ !definition.rootNodeIDs.contains($0.sourceNodeID) }) else {
            throw ModelValidationError.invalidComponentReference
        }
        for slot in slots {
            var parent = byID[slot.sourceNodeID]?.parent
            var visited = Set<NodeID>()
            while case .node(let ancestor)? = parent {
                guard visited.insert(ancestor).inserted, !slotNodeIDs.contains(ancestor) else {
                    throw ModelValidationError.invalidComponentReference
                }
                parent = byID[ancestor]?.parent
            }
        }
    }
}

typealias ComponentVisibilityPropertyID = StableIdentifier<ComponentVisibilityPropertyIdentifierDomain>

struct ExposedComponentVisibilityProperty: Equatable, Identifiable, Sendable {
    let id: ComponentVisibilityPropertyID
    let sourceNodeID: NodeID
    let label: String
    let defaultValue: Bool
}

/// One Boolean binding owns the entire definition child. Derived visibility
/// is resolved before layout/rendering; instance overrides never mutate the
/// definition or the virtual child graph.
enum CanonicalComponentVisibility {
    static let namespace = "component.exposedVisibility.v1."
    static let overrideNamespace = "component.instance.v1.visibility."
    static let metadataKeys = Set([namespace + "id", namespace + "label", namespace + "type", namespace + "default"])
    static let maximumProperties = 64
    static let eligibleKinds: Set<NodeKind> = [.frame, .text, .section, .stack, .grid, .image, .button, .link, .form]

    static func validLabel(_ label: String) -> Bool { CanonicalComponentText.validLabel(label) }
    static func overrideKey(_ id: ComponentVisibilityPropertyID) -> String { overrideNamespace + id.description }
    static func overrideID(_ key: String) -> ComponentVisibilityPropertyID? {
        guard key.hasPrefix(overrideNamespace) else { return nil }
        let raw = String(key.dropFirst(overrideNamespace.count))
        guard let id = ComponentVisibilityPropertyID(uuidString: raw), id.description == raw else { return nil }
        return id
    }
    static func property(on node: DocumentNode) -> ExposedComponentVisibilityProperty? {
        guard eligibleKinds.contains(node.kind),
              let raw = node.insertionProperty(namespace + "id"),
              case .string(let identifier) = raw.value,
              let id = ComponentVisibilityPropertyID(uuidString: identifier), id.description == identifier,
              let label = node.insertionProperty(namespace + "label"), case .string(let name) = label.value,
              let fallback = node.insertionProperty(namespace + "default"),
              case .boolean(let value) = fallback.value else { return nil }
        return .init(id: id, sourceNodeID: node.id, label: name, defaultValue: value)
    }
    static func properties(in definition: DocumentPage) -> [ExposedComponentVisibilityProperty] {
        definition.nodes.compactMap(property)
    }
    static func overrides(on instance: DocumentNode) -> [ComponentVisibilityPropertyID: Bool] {
        var result: [ComponentVisibilityPropertyID: Bool] = [:]
        for property in instance.properties {
            if let id = overrideID(property.key.rawValue), case .boolean(let value) = property.value { result[id] = value }
        }
        return result
    }
    static func unresolvedOverrides(on instance: DocumentNode, definition: DocumentPage) -> Set<ComponentVisibilityPropertyID> {
        Set(overrides(on: instance).keys).subtracting(properties(in: definition).map(\.id))
    }
    static func resolvedVisible(for node: DocumentNode, overrides: [ComponentVisibilityPropertyID: Bool]) -> Bool {
        guard let binding = property(on: node) else {
            return node.insertionProperty("hidden")?.value != .boolean(true)
        }
        return overrides[binding.id] ?? binding.defaultValue
    }
    static func validate(_ node: DocumentNode, inDefinition: Bool) throws {
        let metadata = node.properties.filter { $0.key.rawValue.hasPrefix(namespace) }
        if !metadata.isEmpty {
            guard inDefinition, eligibleKinds.contains(node.kind),
                  Set(metadata.map(\.key.rawValue)) == metadataKeys,
                  metadata.allSatisfy({ $0.origin == .authored }),
                  let binding = property(on: node), validLabel(binding.label),
                  node.insertionProperty(namespace + "type")?.value == .string("boolean-visibility") else {
                throw ModelValidationError.invalidComponentReference
            }
        }
        let overrides = node.properties.filter { $0.key.rawValue.hasPrefix(overrideNamespace) }
        guard overrides.count <= maximumProperties else { throw ModelValidationError.invalidComponentReference }
        for property in overrides {
            guard node.kind == .component, overrideID(property.key.rawValue) != nil,
                  property.origin == .authored, case .boolean = property.value else {
                throw ModelValidationError.invalidComponentReference
            }
        }
    }
    static func validateTransition(from old: CanonicalDocument, to new: CanonicalDocument) throws {
        let oldDefinitions = Dictionary(uniqueKeysWithValues: old.componentDefinitions.map { ($0.id, $0) })
        let newDefinitions = Dictionary(uniqueKeysWithValues: new.componentDefinitions.map { ($0.id, $0) })
        let newNodes = Dictionary(uniqueKeysWithValues: new.pages.flatMap(\.nodes).map { ($0.id, $0) })
        for instance in old.pages.flatMap(\.nodes) {
            guard let definitionID = CanonicalComponentReference.definitionID(for: instance),
                  let oldDefinition = oldDefinitions[definitionID],
                  let newInstance = newNodes[instance.id], newInstance.kind == .component else { continue }
            let oldOverrides = overrides(on: instance), newOverrides = overrides(on: newInstance)
            let retained = Set(oldOverrides.keys).intersection(newOverrides.keys)
            guard retained.isEmpty || CanonicalComponentReference.definitionID(for: newInstance) == definitionID else {
                throw ModelValidationError.componentVisibilityIntentWouldBeLost
            }
            let prior = Dictionary(uniqueKeysWithValues: properties(in: oldDefinition).map { ($0.id, $0.sourceNodeID) })
            let current = Dictionary(uniqueKeysWithValues: (newDefinitions[definitionID].map(properties) ?? []).map { ($0.id, $0.sourceNodeID) })
            for id in retained where prior[id] != nil {
                if let newSource = current[id], newSource != prior[id] {
                    throw ModelValidationError.componentVisibilityIntentWouldBeLost
                }
            }
        }
    }
}

// SF-0905 v1: the canonical component reference plus the typed exposed-property
// identity is the stable override path. The source node is resolved from the
// definition rather than copied into an instance, so definition edits cannot
// create a second source of truth. Existing instance property IDs remain the
// stable authored-value identities used by history and persistence.
// MARK: - OD-033 component variants (SF-0904, document schema 26)

enum ComponentVariantAxisIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "component-variant-axis"
}
typealias ComponentVariantAxisID = StableIdentifier<ComponentVariantAxisIdentifierDomain>

enum ComponentVariantValueIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "component-variant-value"
}
typealias ComponentVariantValueID = StableIdentifier<ComponentVariantValueIdentifierDomain>

struct CanonicalVariantValue: Equatable, Hashable, Sendable {
    let id: ComponentVariantValueID
    let name: String
}

/// SF-0904-001: one named dimension of a component's variants ("Size") with
/// its ordered values ("Small", "Large") and the value copies use by default.
struct CanonicalVariantAxis: Equatable, Hashable, Sendable {
    let id: ComponentVariantAxisID
    let name: String
    let values: [CanonicalVariantValue]
    let defaultValueID: ComponentVariantValueID

    var defaultValue: CanonicalVariantValue? { values.first { $0.id == defaultValueID } }
}

/// One value per axis, in axis order: the identity of one variant.
struct CanonicalVariantCombination: Hashable, Sendable {
    let valueIDs: [ComponentVariantValueID]

    init(_ valueIDs: [ComponentVariantValueID]) { self.valueIDs = valueIDs }

    /// Canonical spelling: value IDs in axis order joined by "+".
    var key: String { valueIDs.map(\.description).joined(separator: "+") }

    static func parse(_ key: String) -> Self? {
        let parts = key.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        let ids = parts.compactMap(ComponentVariantValueID.init(uuidString:))
        guard !parts.isEmpty, ids.count == parts.count,
              zip(ids, parts).allSatisfy({ $0.description == $1 }) else { return nil }
        return Self(ids)
    }
}

/// Where a variant override applies, and where an edit made while editing a
/// variant is stored: one axis value, or one exact combination (two or more
/// axes only).
enum CanonicalVariantTarget: Hashable, Sendable {
    case value(ComponentVariantValueID)
    case combination(CanonicalVariantCombination)

    var keySegment: String {
        switch self {
        case .value(let id): id.description
        case .combination(let combination): combination.key
        }
    }

    static func parse(_ segment: String) -> Self? {
        if segment.contains("+") { return CanonicalVariantCombination.parse(segment).map(Self.combination) }
        guard let id = ComponentVariantValueID(uuidString: segment), id.description == segment else { return nil }
        return .value(id)
    }
}

/// SF-0904-001/003: a definition's validated variant axes and the
/// combinations copies may not choose (every combination is allowed unless
/// listed; the default combination is always allowed).
struct CanonicalVariantSet: Equatable, Sendable {
    let axes: [CanonicalVariantAxis]
    let disallowed: Set<String>

    var defaultCombination: CanonicalVariantCombination { .init(axes.map(\.defaultValueID)) }
    var combinationCount: Int { axes.reduce(1) { $0 * $1.values.count } }

    func isCombination(_ combination: CanonicalVariantCombination) -> Bool {
        combination.valueIDs.count == axes.count && zip(axes, combination.valueIDs).allSatisfy { axis, valueID in
            axis.values.contains { $0.id == valueID }
        }
    }

    func isAllowed(_ combination: CanonicalVariantCombination) -> Bool {
        isCombination(combination) && !disallowed.contains(combination.key)
    }

    func axis(containing valueID: ComponentVariantValueID) -> CanonicalVariantAxis? {
        axes.first { axis in axis.values.contains { $0.id == valueID } }
    }

    func value(_ id: ComponentVariantValueID) -> CanonicalVariantValue? {
        for axis in axes { if let value = axis.values.first(where: { $0.id == id }) { return value } }
        return nil
    }

    /// Every combination, first axis slowest, bounded by
    /// `CanonicalComponentVariants.maximumCombinations` by validation.
    var combinations: [CanonicalVariantCombination] {
        var result: [[ComponentVariantValueID]] = [[]]
        for axis in axes {
            result = result.flatMap { prefix in axis.values.map { prefix + [$0.id] } }
        }
        return result.map(CanonicalVariantCombination.init)
    }

    /// The targets whose overrides apply to `combination`, lowest precedence
    /// first: each chosen value in axis order, then the exact combination.
    func targets(for combination: CanonicalVariantCombination) -> [CanonicalVariantTarget] {
        combination.valueIDs.map(CanonicalVariantTarget.value) + (axes.count > 1 ? [.combination(combination)] : [])
    }

    /// "Large · Primary" — value names in axis order.
    func name(of combination: CanonicalVariantCombination) -> String {
        combination.valueIDs.map { value($0)?.name ?? "Unavailable value" }.joined(separator: " · ")
    }

    func name(of target: CanonicalVariantTarget) -> String {
        switch target {
        case .value(let id):
            guard let owner = axis(containing: id), let entry = value(id) else { return "Unavailable value" }
            return "\(owner.name): \(entry.name)"
        case .combination(let combination): return name(of: combination)
        }
    }
}

/// SF-0904-003: why a copy shows the value it shows for one axis.
enum CanonicalVariantChoiceSource: String, Equatable, Sendable {
    /// The copy chose this value.
    case authored
    /// The copy chose nothing for this axis; the axis default applies.
    case defaultValue = "default"
    /// The copy's stored choice is unavailable; the default applies until repaired.
    case fallback
}

/// SF-0904-004: a copy's stored variant choice that cannot be honored. The
/// stored intent is kept unchanged; the copy shows the default until the user
/// repairs it. Findings carry stable identities only, never authored names.
enum CanonicalVariantFinding: Equatable, Hashable, Sendable {
    case unknownAxis(axis: String)
    case unknownValue(axis: ComponentVariantAxisID, value: String)
    case disallowedCombination(CanonicalVariantCombination)

    var code: String {
        switch self {
        case .unknownAxis: "variant-axis-unavailable"
        case .unknownValue: "variant-value-unavailable"
        case .disallowedCombination: "variant-combination-not-allowed"
        }
    }

    var explanation: String {
        switch self {
        case .unknownAxis:
            "This copy chose a value for a variant property the original no longer has. The choice is kept; the copy shows the default. Use Default to remove it."
        case .unknownValue:
            "This copy chose a variant value the original no longer has. The choice is kept; the copy shows the default value. Choose another value or use the default."
        case .disallowedCombination:
            "This copy's combination of variant values is no longer allowed. The choices are kept; the copy shows the default variant. Choose an allowed combination."
        }
    }
}

struct CanonicalVariantResolution: Equatable, Sendable {
    let combination: CanonicalVariantCombination
    let sources: [ComponentVariantAxisID: CanonicalVariantChoiceSource]
    let findings: [CanonicalVariantFinding]
}

/// SF-0904-001…005, OD-033 (ADR-0029): property-only component variants.
///
/// Storage (definition root node): `axes` (ordered axis IDs),
/// `axis.<axis>.name|values|default`, `value.<value>.name`, optional
/// `disallowed` (sorted combination keys). Overrides live on any definition
/// node as `override.<target>.<propertyKey>` (a value) and
/// `unset.<target>.<propertyKey>` (`true`: the property is absent in that
/// target); `<target>` is a value ID or a combination key. Copies store one
/// `component.instance.v1.variant.<axis>` = value ID per chosen axis; an axis
/// without a choice uses its default. Structure never varies: only the
/// variant-capable properties below may be overridden.
enum CanonicalComponentVariants {
    static let namespace = "component.variant.v1."
    /// The document schema that introduced variants.
    static let documentSchema = 26
    static let axesKey = namespace + "axes"
    static let disallowedKey = namespace + "disallowed"
    static let overridePrefix = namespace + "override."
    static let unsetPrefix = namespace + "unset."
    static let choicePrefix = CanonicalComponentReference.namespace + "variant."
    static let maximumAxes = 4
    static let maximumValuesPerAxis = 16
    static let maximumCombinations = 256
    static let maximumOverrides = 4_096
    static let maximumChoicesPerInstance = 64

    static func axisKey(_ id: ComponentVariantAxisID, _ field: String) -> String {
        namespace + "axis.\(id.description).\(field)"
    }
    static func valueNameKey(_ id: ComponentVariantValueID) -> String { namespace + "value.\(id.description).name" }
    static func overrideKey(_ target: CanonicalVariantTarget, _ propertyKey: String) -> String {
        overridePrefix + target.keySegment + "." + propertyKey
    }
    static func unsetKey(_ target: CanonicalVariantTarget, _ propertyKey: String) -> String {
        unsetPrefix + target.keySegment + "." + propertyKey
    }
    static func choiceKey(_ axis: ComponentVariantAxisID) -> String { choicePrefix + axis.description }

    static func isOverrideKey(_ key: String) -> Bool { key.hasPrefix(overridePrefix) || key.hasPrefix(unsetPrefix) }
    static func isMetadataKey(_ key: String) -> Bool { key.hasPrefix(namespace) && !isOverrideKey(key) }
    static func isChoiceKey(_ key: String) -> Bool { key.hasPrefix(choicePrefix) }

    /// SF-0904-001: properties a variant may change. Geometry, visibility,
    /// text, control labels and appearance (`style.*`). Never structure,
    /// identities, component bindings, links, sizing modes, responsive
    /// overrides, or references that transfer remaps (color tokens, image
    /// assets, reusable styles): an override key is not remapped, so such a
    /// reference could dangle after copy or import.
    static func isVariantCapable(_ key: String) -> Bool {
        if ["layout.x", "layout.y", "layout.width", "layout.height", "hidden", "content.text",
            CanonicalLinkTarget.labelKey].contains(key) { return true }
        guard key.hasPrefix("style.") else { return false }
        return !key.hasPrefix(CanonicalReusableStyleIndex.namespace)
            && !key.hasPrefix(LocalColorTokenBinding.prefix)
            && key != LocalColorTokenBinding.legacyKey
            && key != CanonicalImageFill.assetKey
            && !key.hasPrefix(CanonicalImageStyle.namespace)
    }

    static func rootNode(of definition: DocumentPage) -> DocumentNode? {
        guard let rootID = definition.rootNodeIDs.first else { return nil }
        return definition.nodes.first { $0.id == rootID }
    }

    /// Cheap check used on every expansion: a definition without the axes key
    /// has no variant data (validation guarantees it).
    static func hasVariants(_ definition: DocumentPage) -> Bool {
        rootNode(of: definition)?.properties.contains { $0.key.rawValue == axesKey } == true
    }

    /// The definition's variants, or nil when it has none. Strict: any
    /// partial, duplicated, non-canonical or out-of-range metadata throws.
    static func variantSet(in definition: DocumentPage) throws -> CanonicalVariantSet? {
        let invalid = ModelValidationError.invalidComponentVariants
        guard let root = rootNode(of: definition) else { return nil }
        let owned = root.properties.filter { isMetadataKey($0.key.rawValue) }
        guard !owned.isEmpty else { return nil }
        var byKey: [String: PropertyValue] = [:]
        for property in owned {
            guard property.origin == .authored, byKey.updateValue(property.value, forKey: property.key.rawValue) == nil else {
                throw invalid
            }
        }
        func string(_ key: String) throws -> String {
            guard case .string(let value)? = byKey[key] else { throw invalid }
            return value
        }
        func identifiers<Domain: StableIdentifierDomain>(_ raw: String,
                                                         _ make: (String) -> StableIdentifier<Domain>?) throws -> [StableIdentifier<Domain>] {
            let parts = raw.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            let ids = parts.compactMap(make)
            guard !parts.isEmpty, ids.count == parts.count, zip(ids, parts).allSatisfy({ $0.description == $1 }),
                  Set(ids).count == ids.count else { throw invalid }
            return ids
        }
        var expected: Set<String> = [axesKey]
        let axisIDs = try identifiers(string(axesKey), ComponentVariantAxisID.init(uuidString:))
        guard (1...maximumAxes).contains(axisIDs.count) else { throw invalid }
        var axes: [CanonicalVariantAxis] = []
        var seenValues = Set<ComponentVariantValueID>()
        for axisID in axisIDs {
            let nameKey = axisKey(axisID, "name"), valuesKey = axisKey(axisID, "values"), defaultKey = axisKey(axisID, "default")
            expected.formUnion([nameKey, valuesKey, defaultKey])
            let name = try string(nameKey)
            guard CanonicalComponentText.validLabel(name) else { throw invalid }
            let valueIDs = try identifiers(string(valuesKey), ComponentVariantValueID.init(uuidString:))
            guard (2...maximumValuesPerAxis).contains(valueIDs.count), seenValues.isDisjoint(with: valueIDs) else { throw invalid }
            seenValues.formUnion(valueIDs)
            var values: [CanonicalVariantValue] = []
            for valueID in valueIDs {
                let key = valueNameKey(valueID)
                expected.insert(key)
                let valueName = try string(key)
                guard CanonicalComponentText.validLabel(valueName) else { throw invalid }
                values.append(.init(id: valueID, name: valueName))
            }
            guard Set(values.map { $0.name.lowercased() }).count == values.count else { throw invalid }
            let defaultRaw = try string(defaultKey)
            guard let defaultID = ComponentVariantValueID(uuidString: defaultRaw), defaultID.description == defaultRaw,
                  valueIDs.contains(defaultID) else { throw invalid }
            axes.append(.init(id: axisID, name: name, values: values, defaultValueID: defaultID))
        }
        guard Set(axes.map { $0.name.lowercased() }).count == axes.count,
              axes.reduce(1, { $0 * $1.values.count }) <= maximumCombinations else { throw invalid }
        var disallowed = Set<String>()
        if let raw = byKey[disallowedKey] {
            expected.insert(disallowedKey)
            guard case .string(let list) = raw, !list.isEmpty else { throw invalid }
            let keys = list.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard keys == keys.sorted(), Set(keys).count == keys.count else { throw invalid }
            let unrestricted = CanonicalVariantSet(axes: axes, disallowed: [])
            for key in keys {
                guard let combination = CanonicalVariantCombination.parse(key), unrestricted.isCombination(combination),
                      combination != unrestricted.defaultCombination else { throw invalid }
            }
            disallowed = Set(keys)
        }
        guard Set(byKey.keys) == expected else { throw invalid }
        return .init(axes: axes, disallowed: disallowed)
    }

    /// One node's overrides, by target. `values` holds the authored override
    /// properties keyed by the property key they replace; `unset` the keys a
    /// target removes.
    struct NodeOverrides: Equatable, Sendable {
        var values: [CanonicalVariantTarget: [String: NodeProperty]] = [:]
        var unset: [CanonicalVariantTarget: Set<String>] = [:]

        var isEmpty: Bool { values.isEmpty && unset.isEmpty }
        var count: Int { values.values.reduce(0) { $0 + $1.count } + unset.values.reduce(0) { $0 + $1.count } }
        var targets: Set<CanonicalVariantTarget> { Set(values.keys).union(unset.keys) }
    }

    static func overrides(on node: DocumentNode) throws -> NodeOverrides {
        let invalid = ModelValidationError.invalidComponentVariants
        var result = NodeOverrides()
        for property in node.properties {
            let key = property.key.rawValue
            let isUnset: Bool
            let rest: Substring
            if key.hasPrefix(overridePrefix) {
                isUnset = false; rest = key.dropFirst(overridePrefix.count)
            } else if key.hasPrefix(unsetPrefix) {
                isUnset = true; rest = key.dropFirst(unsetPrefix.count)
            } else { continue }
            guard property.origin == .authored, let dot = rest.firstIndex(of: "."),
                  let target = CanonicalVariantTarget.parse(String(rest[..<dot])) else { throw invalid }
            let propertyKey = String(rest[rest.index(after: dot)...])
            guard isVariantCapable(propertyKey) else { throw invalid }
            if isUnset {
                guard property.value == .boolean(true), result.values[target]?[propertyKey] == nil,
                      result.unset[target, default: []].insert(propertyKey).inserted else { throw invalid }
            } else {
                guard result.unset[target]?.contains(propertyKey) != true,
                      result.values[target]?[propertyKey] == nil else { throw invalid }
                result.values[target, default: [:]][propertyKey] = property
            }
        }
        return result
    }

    /// `node` as it appears with `targets` applied in order. Overrides and
    /// unset markers are removed (and metadata unless `keepingMetadata`). An
    /// overridden property keeps the base property's identity; a property
    /// only a variant adds uses the override's identity, so identities stay
    /// unique and stable across reopen.
    static func resolvedNode(_ node: DocumentNode, overrides: NodeOverrides, targets: [CanonicalVariantTarget],
                             keepingMetadata: Bool = false) -> DocumentNode {
        var copy = node
        copy.properties.removeAll { property in
            let key = property.key.rawValue
            return isOverrideKey(key) || (!keepingMetadata && isMetadataKey(key))
        }
        guard !overrides.isEmpty else { return copy }
        for target in targets {
            if let removed = overrides.unset[target] {
                copy.properties.removeAll { removed.contains($0.key.rawValue) }
            }
            guard let values = overrides.values[target] else { continue }
            for (key, authored) in values.sorted(by: { $0.key < $1.key }) {
                if let index = copy.properties.firstIndex(where: { $0.key.rawValue == key }) {
                    copy.properties[index].value = authored.value
                    copy.properties[index].origin = .authored
                } else {
                    copy.properties.append(NodeProperty(id: authored.id, key: .init(rawValue: key),
                                                        value: authored.value, origin: .authored))
                }
            }
        }
        return copy
    }

    /// The definition with `targets` applied to every node.
    static func resolved(_ definition: DocumentPage, targets: [CanonicalVariantTarget],
                         keepingMetadata: Bool = false) -> DocumentPage {
        var page = definition
        page.nodes = definition.nodes.map { node in
            let nodeOverrides = (try? Self.overrides(on: node)) ?? NodeOverrides()
            return resolvedNode(node, overrides: nodeOverrides, targets: targets, keepingMetadata: keepingMetadata)
        }
        return page
    }

    /// SF-0904-003/004: the variant a copy shows. A stored choice for an axis
    /// or value the definition no longer has, or a combination that is no
    /// longer allowed, is kept on the copy and reported; the copy then shows
    /// the default (per axis for an unavailable value, the whole default
    /// combination for a disallowed one).
    static func resolution(for instance: DocumentNode, set: CanonicalVariantSet) -> CanonicalVariantResolution {
        let axesByID = Dictionary(uniqueKeysWithValues: set.axes.map { ($0.id, $0) })
        var chosen: [ComponentVariantAxisID: ComponentVariantValueID] = [:]
        var fellBack = Set<ComponentVariantAxisID>()
        var findings: [CanonicalVariantFinding] = []
        for property in instance.properties where isChoiceKey(property.key.rawValue) {
            let raw = String(property.key.rawValue.dropFirst(choicePrefix.count))
            guard let axisID = ComponentVariantAxisID(uuidString: raw), let axis = axesByID[axisID] else {
                findings.append(.unknownAxis(axis: raw)); continue
            }
            guard case .string(let value) = property.value, let valueID = ComponentVariantValueID(uuidString: value),
                  axis.values.contains(where: { $0.id == valueID }) else {
                var stored = ""
                if case .string(let value) = property.value { stored = value }
                findings.append(.unknownValue(axis: axisID, value: stored))
                fellBack.insert(axisID)
                continue
            }
            chosen[axisID] = valueID
        }
        let candidate = CanonicalVariantCombination(set.axes.map { chosen[$0.id] ?? $0.defaultValueID })
        guard set.isAllowed(candidate) else {
            findings.append(.disallowedCombination(candidate))
            return .init(combination: set.defaultCombination,
                         sources: Dictionary(uniqueKeysWithValues: set.axes.map { ($0.id, .fallback) }),
                         findings: findings)
        }
        let sources = Dictionary(uniqueKeysWithValues: set.axes.map { axis -> (ComponentVariantAxisID, CanonicalVariantChoiceSource) in
            (axis.id, chosen[axis.id] != nil ? .authored : fellBack.contains(axis.id) ? .fallback : .defaultValue)
        })
        return .init(combination: candidate, sources: sources, findings: findings)
    }

    /// The definition an instance draws. Unchanged (and cheap) when the
    /// definition has no variants. Only valid documents are drawn, so a
    /// malformed set cannot occur here; it would draw the base definition.
    static func resolvedDefinition(_ definition: DocumentPage, for instance: DocumentNode) -> DocumentPage {
        guard hasVariants(definition) else { return definition }
        guard let set = try? variantSet(in: definition) else { return resolved(definition, targets: []) }
        return resolved(definition, targets: set.targets(for: resolution(for: instance, set: set).combination))
    }

    /// Per-node rules: overrides only inside definitions, metadata only on
    /// the definition root, copy choices well formed (their meaning is
    /// resolved against the definition, so an unknown choice stays valid).
    static func validate(_ node: DocumentNode, inDefinition: Bool, isDefinitionRoot: Bool) throws {
        let invalid = ModelValidationError.invalidComponentVariants
        for property in node.properties {
            let key = property.key.rawValue
            if key.hasPrefix(namespace) {
                guard inDefinition, isDefinitionRoot || isOverrideKey(key) else { throw invalid }
            }
        }
        let choices = node.properties.filter { isChoiceKey($0.key.rawValue) }
        guard !choices.isEmpty else { return }
        guard node.kind == .component, choices.count <= maximumChoicesPerInstance else { throw invalid }
        for property in choices {
            let raw = String(property.key.rawValue.dropFirst(choicePrefix.count))
            guard property.origin == .authored,
                  let axis = ComponentVariantAxisID(uuidString: raw), axis.description == raw,
                  case .string(let value) = property.value,
                  let valueID = ComponentVariantValueID(uuidString: value), valueID.description == value else {
                throw invalid
            }
        }
    }

    /// SF-0904-001/004: a definition's variants are valid and every variant a
    /// copy can show is itself a valid definition. Each distinct variant that
    /// authored overrides produce is resolved and validated with the same page
    /// rules as the base (structure is unchanged, so only property rules can
    /// fail); variants that no override touches equal the base.
    static func validateDefinition(_ definition: DocumentPage, validatePage: (DocumentPage) throws -> Void) throws {
        let invalid = ModelValidationError.invalidComponentVariants
        let set = try variantSet(in: definition)
        var byNode: [NodeID: NodeOverrides] = [:]
        var total = 0
        for node in definition.nodes {
            let nodeOverrides = try Self.overrides(on: node)
            guard !nodeOverrides.isEmpty else { continue }
            guard let set else { throw invalid }
            for target in nodeOverrides.targets {
                switch target {
                case .value(let id):
                    guard set.value(id) != nil else { throw invalid }
                case .combination(let combination):
                    guard set.axes.count > 1, set.isAllowed(combination) else { throw invalid }
                }
            }
            total += nodeOverrides.count
            byNode[node.id] = nodeOverrides
        }
        guard total <= maximumOverrides else { throw invalid }
        guard let set, !byNode.isEmpty else { return }
        let authoredTargets = Set(byNode.values.flatMap(\.targets))
        var validated = Set<[CanonicalVariantTarget]>()
        for combination in set.combinations where set.isAllowed(combination) {
            let applied = set.targets(for: combination).filter(authoredTargets.contains)
            guard !applied.isEmpty, validated.insert(applied).inserted else { continue }
            var page = definition
            page.nodes = definition.nodes.map { node in
                resolvedNode(node, overrides: byNode[node.id] ?? NodeOverrides(), targets: applied)
            }
            do { try validatePage(page) } catch {
                throw ModelValidationError.componentVariantResolvesInvalid
            }
        }
    }
}

enum ComponentOverridePropertyIdentity: Hashable, Sendable {
    case text(ComponentTextPropertyID)
    case visibility(ComponentVisibilityPropertyID)
    case choice(ComponentChoicePropertyID)
    case media(ComponentMediaPropertyID)
    case action(ComponentActionPropertyID)
    case slot(ComponentSlotPropertyID)

    var stableDescription: String {
        switch self {
        case .text(let id): "text:\(id.description)"
        case .visibility(let id): "visibility:\(id.description)"
        case .choice(let id): "choice:\(id.description)"
        case .media(let id): "media:\(id.description)"
        case .action(let id): "action:\(id.description)"
        case .slot(let id): "slot:\(id.description)"
        }
    }

    var organizationKind: String { String(stableDescription.prefix { $0 != ":" }) }
    static func reference(_ raw: String) -> Self? {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let value = String(parts[1]), identity: Self
        switch parts[0] {
        case "text": guard let id = ComponentTextPropertyID(uuidString: value) else { return nil }; identity = .text(id)
        case "visibility": guard let id = ComponentVisibilityPropertyID(uuidString: value) else { return nil }; identity = .visibility(id)
        case "choice": guard let id = ComponentChoicePropertyID(uuidString: value) else { return nil }; identity = .choice(id)
        case "media": guard let id = ComponentMediaPropertyID(uuidString: value) else { return nil }; identity = .media(id)
        case "action": guard let id = ComponentActionPropertyID(uuidString: value) else { return nil }; identity = .action(id)
        case "slot": guard let id = ComponentSlotPropertyID(uuidString: value) else { return nil }; identity = .slot(id)
        default: return nil
        }
        return identity.stableDescription == raw ? identity : nil
    }
}

/// SF-0902-006/007: discovery is derived UI state, never serialized organization.
/// Search excludes property values (text, URLs and asset content) and preserves
/// the definition's existing order. Recovery remains outside this filter.
enum ComponentPropertyDiscovery {
    struct Result: Equatable, Sendable {
        let entries: [CanonicalComponentOrganization.Entry]
        let total: Int
        let hiddenConflictCount: Int
        func neighbor(of current: ComponentOverridePropertyIdentity?, offset: Int) -> ComponentOverridePropertyIdentity? {
            guard !entries.isEmpty else { return nil }
            guard let current, let index = entries.firstIndex(where: { $0.id == current }) else {
                return offset < 0 ? entries.last?.id : entries.first?.id
            }
            return entries[min(max(index + offset, 0), entries.count - 1)].id
        }
    }
    static func project(_ entries: [CanonicalComponentOrganization.Entry], query: String,
                        authored: Set<ComponentOverridePropertyIdentity>,
                        conflicts: Set<ComponentOverridePropertyIdentity>, conflictsOnly: Bool = false) -> Result {
        let tokens = normalize(String(query.prefix(256))).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let visible = entries.filter { entry in
            let provenance = conflicts.contains(entry.id) ? "conflict unavailable retained custom value needs attention missing original" :
                authored.contains(entry.id) ? "authored override set here change this copy custom value" : "inherited default definition original uses component default"
            let searchable = normalize([entry.label, entry.group ?? "ungrouped", entry.id.organizationKind,
                                        entry.id.organizationKind == "slot" ? "fallback default contents top-level items original" : "", provenance].joined(separator: " "))
            return (!conflictsOnly || conflicts.contains(entry.id)) && tokens.allSatisfy(searchable.contains)
        }
        return Result(entries: visible, total: entries.count,
                      hiddenConflictCount: conflicts.subtracting(Set(visible.map(\.id))).count)
    }
    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// A definition's root owns one optional authored note. Absence is the
/// default and carries no property identity or serialized placeholder.
enum CanonicalComponentUsageNotes {
    static let namespace = "component.documentation."
    static let key = namespace + "v1.usageNotes"
    static let documentSchema = 20
    static let maximumBytes = 4_096

    static func owns(_ property: NodeProperty) -> Bool {
        property.key.rawValue.hasPrefix(namespace)
    }

    static func normalized(_ draft: String) throws -> String? {
        let lines = draft.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !lines.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t"
        }) else { throw ModelValidationError.invalidComponentUsageNotes }
        let value = lines.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count <= maximumBytes else { throw ModelValidationError.invalidComponentUsageNotes }
        return value.isEmpty ? nil : value
    }

    static func text(in definition: DocumentPage) -> String? {
        guard definition.role == .componentDefinition, let rootID = definition.rootNodeIDs.first else { return nil }
        return definition.nodes.first { $0.id == rootID }?.insertionStringProperty(key)
    }

    static func validate(_ node: DocumentNode, isDefinitionRoot: Bool) throws {
        let properties = node.properties.filter(owns)
        guard !properties.isEmpty else { return }
        guard isDefinitionRoot, properties.count == 1, let property = properties.first,
              property.key.rawValue == key, property.origin == .authored,
              case .string(let value) = property.value, let normalized = try normalized(value),
              value.utf8.elementsEqual(normalized.utf8) else { throw ModelValidationError.invalidComponentUsageNotes }
    }
}

/// Definition-owned presentation metadata references the existing typed binding;
/// it never duplicates defaults, overrides, child order, or slot ownership.
enum CanonicalComponentOrganization {
    static let namespace = "component.organization.v1."
    static let kinds = ["text", "visibility", "choice", "media", "action", "slot"]
    struct Entry: Identifiable, Equatable, Sendable {
        let id: ComponentOverridePropertyIdentity
        let sourceNodeID: NodeID
        let label: String
        let group: String?
        let rank: Int?
    }
    static func key(_ kind: String, _ field: String) -> String { namespace + kind + "." + field }
    static func validGroup(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 64
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
    static func bindings(on node: DocumentNode) -> [(ComponentOverridePropertyIdentity, String)] {
        var result: [(ComponentOverridePropertyIdentity, String)] = []
        if let p = CanonicalComponentText.property(on: node) { result.append((.text(p.id), p.label)) }
        if let p = CanonicalComponentVisibility.property(on: node) { result.append((.visibility(p.id), p.label)) }
        if let p = CanonicalComponentChoice.property(on: node) { result.append((.choice(p.id), p.label)) }
        if let p = CanonicalComponentMedia.property(on: node) { result.append((.media(p.id), p.label)) }
        if let p = CanonicalComponentAction.property(on: node) { result.append((.action(p.id), p.label)) }
        if let p = CanonicalComponentSlot.property(on: node) { result.append((.slot(p.id), p.label)) }
        return result
    }
    static func entries(in definition: DocumentPage) -> [Entry] {
        // Canonical ownership order, not UUID allocation or dictionary order,
        // keeps legacy default presentation stable after transfer/remapping.
        let nodes = Dictionary(definition.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var pending = Array(definition.rootNodeIDs.reversed()), ordinal: [NodeID: Int] = [:]
        while let id = pending.popLast(), ordinal.count < 20_000 {
            guard ordinal[id] == nil, let node = nodes[id] else { continue }
            ordinal[id] = ordinal.count; pending.append(contentsOf: node.childIDs.reversed())
        }
        return definition.nodes.flatMap { node in
            bindings(on: node).map { identity, label in
                let rank: Int?
                if case .number(let n) = node.insertionProperty(key(identity.organizationKind, "order"))?.value,
                   n.isFinite, n >= 0, n < 64, n.rounded() == n { rank = Int(n) } else { rank = nil }
                return Entry(id: identity, sourceNodeID: node.id, label: label,
                    group: node.insertionStringProperty(key(identity.organizationKind, "group")), rank: rank)
            }
        }.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return (lhs.rank ?? 64) < (rhs.rank ?? 64) }
            if lhs.id.organizationKind != rhs.id.organizationKind { return lhs.id.organizationKind < rhs.id.organizationKind }
            if ordinal[lhs.sourceNodeID] != ordinal[rhs.sourceNodeID] {
                return (ordinal[lhs.sourceNodeID] ?? 20_000) < (ordinal[rhs.sourceNodeID] ?? 20_000)
            }
            return lhs.id.stableDescription < rhs.id.stableDescription
        }
    }
    static func validate(_ node: DocumentNode, inDefinition: Bool) throws {
        let metadata = node.properties.filter { $0.key.rawValue.hasPrefix(namespace) }
        guard !metadata.isEmpty else { return }
        let bindings = bindings(on: node).map(\.0)
        let boundKinds = Set(bindings.map(\.organizationKind))
        guard inDefinition, metadata.count <= kinds.count * 3 else { throw ModelValidationError.invalidComponentReference }
        for binding in bindings where metadata.contains(where: { $0.key.rawValue.hasPrefix(namespace + binding.organizationKind + ".") }) {
            guard node.insertionStringProperty(key(binding.organizationKind, "binding")) == binding.stableDescription,
                  metadata.contains(where: { $0.key.rawValue == key(binding.organizationKind, "order") || $0.key.rawValue == key(binding.organizationKind, "group") }) else {
                throw ModelValidationError.invalidComponentReference
            }
        }
        for property in metadata {
            let parts = property.key.rawValue.dropFirst(namespace.count).split(separator: ".")
            guard parts.count == 2, boundKinds.contains(String(parts[0])), property.origin == .authored,
                  property.key.rawValue == key(String(parts[0]), String(parts[1])) else {
                throw ModelValidationError.invalidComponentReference
            }
            switch (parts[1], property.value) {
            case ("binding", .string(let raw)) where ComponentOverridePropertyIdentity.reference(raw)?.organizationKind == String(parts[0]): break
            case ("group", .string(let name)) where validGroup(name): break
            case ("order", .number(let n)) where n.isFinite && n >= 0 && n < 64 && n.rounded() == n: break
            default: throw ModelValidationError.invalidComponentReference
            }
        }
    }
    static func validateDefinition(_ definition: DocumentPage) throws {
        let entries = entries(in: definition)
        let ranks = entries.compactMap(\.rank)
        guard Set(ranks).count == ranks.count else { throw ModelValidationError.invalidComponentReference }
    }
}

struct ComponentOverridePathV1: Hashable, Sendable {
    static let version = 1
    let definitionID: PageID
    let sourceNodeID: NodeID
    let property: ComponentOverridePropertyIdentity
}

enum ComponentOverrideValue: Equatable, Sendable {
    case text(String)
    case visibility(Bool)
    case choice(ImageFitMode)
    case media(AssetID)
    case action(CanonicalLinkTarget)
    case slotFallback([NodeID])
    /// OD-018: authored empty slot.
    case slotEmpty
    /// OD-018: the instance supplies its own slot contents.
    case slotSupplied
}

enum ComponentOverrideConflict: String, Equatable, Sendable {
    case missingDefinition = "missing-definition"
    case missingProperty = "missing-property"
    case missingActionDestination = "missing-action-destination"

    var explanation: String {
        switch self {
        case .missingDefinition: "The original component is unavailable. Your custom value is kept. Recover the original with Undo or the original saved project; removing this value does not restore it."
        case .missingProperty: "The original component property is unavailable. Your custom value is kept. Recover that property with Undo or the original saved project, or remove this custom value."
        case .missingActionDestination: "This custom destination is unavailable. Your choice is kept. Choose an available destination, or remove the custom value; a deleted destination is not restored."
        }
    }
}

enum ComponentOverrideResolution: Equatable, Sendable {
    case inherited
    case authored(propertyID: PropertyID)
    case conflict(ComponentOverrideConflict, propertyID: PropertyID)
}

struct ResolvedComponentOverride: Equatable, Sendable {
    let property: ComponentOverridePropertyIdentity
    let path: ComponentOverridePathV1?
    let label: String?
    let inheritedValue: ComponentOverrideValue?
    let effectiveValue: ComponentOverrideValue
    let resolution: ComponentOverrideResolution
}

/// A revision-derived view of retained intent, not another recovery store.
/// Only stable IDs/categories may enter diagnostics; values remain Inspector data.
struct ComponentOverrideConflictFinding: Identifiable, Equatable, Sendable {
    let instanceID: NodeID
    let definitionID: PageID
    let property: ComponentOverridePropertyIdentity
    let authoredPropertyID: PropertyID
    let reason: ComponentOverrideConflict
    let path: ComponentOverridePathV1?
    let label: String?
    let retainedValue: ComponentOverrideValue
    var id: String { instanceID.description + ":" + property.stableDescription }
}

/// One bounded immutable projection feeds Inspector provenance, dependency
/// diagnostics, transfer validation, and static-output preflight. Conflicting
/// authored values remain present and resettable; they are never silently
/// reattached to a different source node.
enum CanonicalComponentOverrides {
    static let maximumOverridesPerInstance = 128

    static func requiresRecovery(instance: DocumentNode, document: CanonicalDocument) throws -> Bool {
        guard let id = CanonicalComponentReference.definitionID(for: instance) else {
            throw ModelValidationError.invalidComponentReference
        }
        if !document.componentDefinitions.contains(where: { $0.id == id }) { return true }
        return try !conflicts(instance: instance, document: document).isEmpty
    }

    static func validateSerializableRetention(_ document: CanonicalDocument, checkpoint: () throws -> Void = {}) throws {
        // OD-034: instances inside definitions follow the same retention rules.
        for instance in document.pages.flatMap(\.nodes) where instance.kind == .component {
            try checkpoint()
            // Valid conflicts are intentionally loadable; malformed or over-budget
            // typed override state is rejected by the same projection boundary.
            _ = try conflicts(instance: instance, document: document)
        }
    }

    static func conflicts(instance: DocumentNode, document: CanonicalDocument,
                          definitions: [DocumentPage]? = nil) throws -> [ComponentOverrideConflictFinding] {
        guard let definitionID = CanonicalComponentReference.definitionID(for: instance) else {
            throw ModelValidationError.invalidComponentReference
        }
        return try resolve(instance: instance, document: document, definitions: definitions).compactMap { value in
            guard case .conflict(let reason, let propertyID) = value.resolution else { return nil }
            return .init(instanceID: instance.id, definitionID: definitionID, property: value.property,
                authoredPropertyID: propertyID, reason: reason, path: value.path, label: value.label,
                retainedValue: value.effectiveValue)
        }
    }

    static func resolve(instance: DocumentNode, document: CanonicalDocument,
                        definitions: [DocumentPage]? = nil) throws -> [ResolvedComponentOverride] {
        guard instance.kind == .component,
              let definitionID = CanonicalComponentReference.definitionID(for: instance) else {
            throw ModelValidationError.invalidComponentReference
        }
        let textProperties = instance.properties.compactMap { property -> (ComponentTextPropertyID, NodeProperty)? in
            CanonicalComponentText.overrideID(property.key.rawValue).map { ($0, property) }
        }
        let visibilityProperties = instance.properties.compactMap { property -> (ComponentVisibilityPropertyID, NodeProperty)? in
            CanonicalComponentVisibility.overrideID(property.key.rawValue).map { ($0, property) }
        }
        let choiceProperties = instance.properties.compactMap { property -> (ComponentChoicePropertyID, NodeProperty)? in
            CanonicalComponentChoice.overrideID(property.key.rawValue).map { ($0, property) }
        }
        let mediaProperties = instance.properties.compactMap { property -> (ComponentMediaPropertyID, NodeProperty)? in
            CanonicalComponentMedia.overrideID(property.key.rawValue).map { ($0, property) }
        }
        let actionProperties = instance.properties.compactMap { property -> (ComponentActionPropertyID, NodeProperty)? in
            CanonicalComponentAction.overrideID(property.key.rawValue).map { ($0, property) }
        }
        // OD-018: slot state is part of the instance's authored intent.
        let slotProperties = CanonicalComponentSlot.markers(on: instance).sorted { $0.key.description < $1.key.description }
        guard textProperties.count + visibilityProperties.count + choiceProperties.count + mediaProperties.count + actionProperties.count
                + slotProperties.count <= maximumOverridesPerInstance else {
            throw ModelValidationError.invalidComponentReference
        }
        func slotValue(_ property: NodeProperty) -> ComponentOverrideValue {
            property.value == .string(CanonicalComponentSlot.emptyValue) ? .slotEmpty : .slotSupplied
        }
        guard let baseDefinition = (definitions ?? document.componentDefinitions).first(where: { $0.id == definitionID }) else {
            let unresolvedText = textProperties.compactMap { id, property -> ResolvedComponentOverride? in
                guard case .string(let value) = property.value else { return nil }
                return .init(property: .text(id), path: nil, label: nil, inheritedValue: nil,
                             effectiveValue: .text(value), resolution: .conflict(.missingDefinition, propertyID: property.id))
            }
            let unresolvedVisibility = visibilityProperties.compactMap { id, property -> ResolvedComponentOverride? in
                guard case .boolean(let value) = property.value else { return nil }
                return .init(property: .visibility(id), path: nil, label: nil, inheritedValue: nil,
                             effectiveValue: .visibility(value), resolution: .conflict(.missingDefinition, propertyID: property.id))
            }
            let unresolvedChoice = choiceProperties.compactMap { id, property -> ResolvedComponentOverride? in
                guard case .string(let raw) = property.value, let value = ImageFitMode(rawValue: raw) else { return nil }
                return .init(property: .choice(id), path: nil, label: nil, inheritedValue: nil,
                             effectiveValue: .choice(value), resolution: .conflict(.missingDefinition, propertyID: property.id))
            }
            let unresolvedMedia = mediaProperties.compactMap { id, property -> ResolvedComponentOverride? in
                guard case .string(let raw) = property.value, let value = AssetID(uuidString: raw) else { return nil }
                return .init(property: .media(id), path: nil, label: nil, inheritedValue: nil,
                             effectiveValue: .media(value), resolution: .conflict(.missingDefinition, propertyID: property.id))
            }
            let unresolvedAction = actionProperties.compactMap { id, property -> ResolvedComponentOverride? in
                guard case .string(let raw) = property.value, let value = CanonicalComponentAction.decode(raw) else { return nil }
                return .init(property: .action(id), path: nil, label: nil, inheritedValue: nil,
                             effectiveValue: .action(value), resolution: .conflict(.missingDefinition, propertyID: property.id))
            }
            let unresolvedSlots = slotProperties.map { id, property in
                ResolvedComponentOverride(property: .slot(id), path: nil, label: nil, inheritedValue: nil,
                    effectiveValue: slotValue(property), resolution: .conflict(.missingDefinition, propertyID: property.id))
            }
            return (unresolvedText + unresolvedVisibility + unresolvedChoice + unresolvedMedia + unresolvedAction + unresolvedSlots).sorted { $0.property.stableDescription < $1.property.stableDescription }
        }
        // OD-033: inherited values are the ones the copy's variant shows.
        let definition = CanonicalComponentVariants.resolvedDefinition(baseDefinition, for: instance)

        let authoredText = Dictionary(uniqueKeysWithValues: textProperties.map { ($0.0, $0.1) })
        let authoredVisibility = Dictionary(uniqueKeysWithValues: visibilityProperties.map { ($0.0, $0.1) })
        let authoredChoice = Dictionary(uniqueKeysWithValues: choiceProperties.map { ($0.0, $0.1) })
        let authoredMedia = Dictionary(uniqueKeysWithValues: mediaProperties.map { ($0.0, $0.1) })
        let authoredAction = Dictionary(uniqueKeysWithValues: actionProperties.map { ($0.0, $0.1) })
        var result: [ResolvedComponentOverride] = []
        for exposed in CanonicalComponentText.properties(in: definition) {
            let authored = authoredText[exposed.id]
            let value: ComponentOverrideValue = authored.flatMap {
                if case .string(let value) = $0.value { return .text(value) }
                return nil
            } ?? .text(exposed.defaultValue)
            result.append(.init(property: .text(exposed.id),
                path: .init(definitionID: definitionID, sourceNodeID: exposed.sourceNodeID, property: .text(exposed.id)),
                label: exposed.label, inheritedValue: .text(exposed.defaultValue), effectiveValue: value,
                resolution: authored.map { .authored(propertyID: $0.id) } ?? .inherited))
        }
        for exposed in CanonicalComponentVisibility.properties(in: definition) {
            let authored = authoredVisibility[exposed.id]
            let value: ComponentOverrideValue = authored.flatMap {
                if case .boolean(let value) = $0.value { return .visibility(value) }
                return nil
            } ?? .visibility(exposed.defaultValue)
            result.append(.init(property: .visibility(exposed.id),
                path: .init(definitionID: definitionID, sourceNodeID: exposed.sourceNodeID, property: .visibility(exposed.id)),
                label: exposed.label, inheritedValue: .visibility(exposed.defaultValue), effectiveValue: value,
                resolution: authored.map { .authored(propertyID: $0.id) } ?? .inherited))
        }
        for exposed in CanonicalComponentChoice.properties(in: definition) {
            let authored = authoredChoice[exposed.id]
            let value: ComponentOverrideValue = authored.flatMap {
                if case .string(let raw) = $0.value, let value = ImageFitMode(rawValue: raw) { return .choice(value) }
                return nil
            } ?? .choice(exposed.defaultValue)
            result.append(.init(property: .choice(exposed.id),
                path: .init(definitionID: definitionID, sourceNodeID: exposed.sourceNodeID, property: .choice(exposed.id)),
                label: exposed.label, inheritedValue: .choice(exposed.defaultValue), effectiveValue: value,
                resolution: authored.map { .authored(propertyID: $0.id) } ?? .inherited))
        }
        for exposed in CanonicalComponentMedia.properties(in: definition) {
            let authored = authoredMedia[exposed.id]
            let value: ComponentOverrideValue = authored.flatMap {
                if case .string(let raw) = $0.value, let value = AssetID(uuidString: raw) { return .media(value) }
                return nil
            } ?? .media(exposed.defaultValue)
            result.append(.init(property: .media(exposed.id),
                path: .init(definitionID: definitionID, sourceNodeID: exposed.sourceNodeID, property: .media(exposed.id)),
                label: exposed.label, inheritedValue: .media(exposed.defaultValue), effectiveValue: value,
                resolution: authored.map { .authored(propertyID: $0.id) } ?? .inherited))
        }
        for exposed in CanonicalComponentAction.properties(in: definition) {
            let authored = authoredAction[exposed.id]
            let value: ComponentOverrideValue = authored.flatMap {
                if case .string(let raw) = $0.value, let value = CanonicalComponentAction.decode(raw) { return .action(value) }
                return nil
            } ?? .action(exposed.defaultValue)
            let resolution: ComponentOverrideResolution
            if let authored, case .action(let target) = value, target.isMissing(in: document) {
                resolution = .conflict(.missingActionDestination, propertyID: authored.id)
            } else { resolution = authored.map { .authored(propertyID: $0.id) } ?? .inherited }
            result.append(.init(property: .action(exposed.id),
                path: .init(definitionID: definitionID, sourceNodeID: exposed.sourceNodeID, property: .action(exposed.id)),
                label: exposed.label, inheritedValue: .action(exposed.defaultValue), effectiveValue: value,
                resolution: resolution))
        }
        let slotMarkers = Dictionary(uniqueKeysWithValues: slotProperties.map { ($0.key, $0.value) })
        for exposed in CanonicalComponentSlot.properties(in: definition) {
            let authored = slotMarkers[exposed.id]
            result.append(.init(property: .slot(exposed.id),
                path: .init(definitionID: definitionID, sourceNodeID: exposed.sourceNodeID, property: .slot(exposed.id)),
                label: exposed.label, inheritedValue: .slotFallback(exposed.defaultChildIDs),
                effectiveValue: authored.map(slotValue) ?? .slotFallback(exposed.defaultChildIDs),
                resolution: authored.map { .authored(propertyID: $0.id) } ?? .inherited))
        }
        // A slot the definition no longer exposes keeps its state as a conflict.
        let knownSlots = Set(CanonicalComponentSlot.properties(in: definition).map(\.id))
        for (id, property) in slotProperties where !knownSlots.contains(id) {
            result.append(.init(property: .slot(id), path: nil, label: nil, inheritedValue: nil,
                effectiveValue: slotValue(property), resolution: .conflict(.missingProperty, propertyID: property.id)))
        }
        let knownText = Set(CanonicalComponentText.properties(in: definition).map(\.id))
        for (id, property) in textProperties where !knownText.contains(id) {
            guard case .string(let value) = property.value else { continue }
            result.append(.init(property: .text(id), path: nil, label: nil, inheritedValue: nil,
                effectiveValue: .text(value), resolution: .conflict(.missingProperty, propertyID: property.id)))
        }
        let knownVisibility = Set(CanonicalComponentVisibility.properties(in: definition).map(\.id))
        for (id, property) in visibilityProperties where !knownVisibility.contains(id) {
            guard case .boolean(let value) = property.value else { continue }
            result.append(.init(property: .visibility(id), path: nil, label: nil, inheritedValue: nil,
                effectiveValue: .visibility(value), resolution: .conflict(.missingProperty, propertyID: property.id)))
        }
        let knownChoice = Set(CanonicalComponentChoice.properties(in: definition).map(\.id))
        for (id, property) in choiceProperties where !knownChoice.contains(id) {
            guard case .string(let raw) = property.value, let value = ImageFitMode(rawValue: raw) else { continue }
            result.append(.init(property: .choice(id), path: nil, label: nil, inheritedValue: nil,
                effectiveValue: .choice(value), resolution: .conflict(.missingProperty, propertyID: property.id)))
        }
        let knownMedia = Set(CanonicalComponentMedia.properties(in: definition).map(\.id))
        for (id, property) in mediaProperties where !knownMedia.contains(id) {
            guard case .string(let raw) = property.value, let value = AssetID(uuidString: raw) else { continue }
            result.append(.init(property: .media(id), path: nil, label: nil, inheritedValue: nil,
                effectiveValue: .media(value), resolution: .conflict(.missingProperty, propertyID: property.id)))
        }
        let knownAction = Set(CanonicalComponentAction.properties(in: definition).map(\.id))
        for (id, property) in actionProperties where !knownAction.contains(id) {
            guard case .string(let raw) = property.value, let value = CanonicalComponentAction.decode(raw) else { continue }
            result.append(.init(property: .action(id), path: nil, label: nil, inheritedValue: nil,
                effectiveValue: .action(value), resolution: .conflict(.missingProperty, propertyID: property.id)))
        }
        let order = Dictionary(uniqueKeysWithValues: CanonicalComponentOrganization.entries(in: definition)
            .enumerated().map { ($0.element.id, $0.offset) })
        return result.sorted {
            if order[$0.property] != order[$1.property] { return (order[$0.property] ?? 64) < (order[$1.property] ?? 64) }
            return $0.property.stableDescription < $1.property.stableDescription
        }
    }
}

extension CanonicalDocument {
    var componentDefinitions: [DocumentPage] { pages.filter { $0.role == .componentDefinition } }
    var websitePages: [DocumentPage] { pages.filter { $0.role != .componentDefinition } }
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

/// SF-AUTHORING-106 / SF-0204-001...008 — the sole approved local starter
/// template. The template is ordinary canonical document content: after the
/// clean lifecycle baseline is established, every page, node, and property is
/// edited and removed by the same commands as user-created content. Stable
/// identities are derived from the new document identity so repeated reads of
/// one creation request cannot drift while separate projects never alias.
enum StarterSiteTemplate {
    static let id = TemplateID(UUID(uuidString: "02040000-0000-4000-8000-000000000106")!)
    static let displayName = "Starter Site"
    static let requirementIDs = Set((1...8).map { String(format: "SF-0204-%03d", $0) })

    static func document(id documentID: DocumentID = DocumentID()) -> CanonicalDocument {
        ProjectCreation.template(
            id: documentID,
            templateID: id,
            pages: [
                page(
                    documentID: documentID, label: "home", name: "Home", route: "/", role: .home,
                    title: "A clear place to begin",
                    body: "Replace this text with the purpose of your site.",
                    footer: "Add the details your visitors need."
                ),
                page(
                    documentID: documentID, label: "about", name: "About", route: "/about", role: .standard,
                    title: "About this site",
                    body: "Describe the people, project, or idea behind this site.",
                    footer: "Keep this information current and useful."
                ),
            ]
        )
    }

    private static func page(
        documentID: DocumentID,
        label: String,
        name: String,
        route: String,
        role: PageRole,
        title: String,
        body: String,
        footer: String
    ) -> DocumentPage {
        let pageID = PageID(derived(documentID.rawValue, "starter.\(label).page"))
        let rootID = NodeID(derived(documentID.rawValue, "starter.\(label).root"))
        let headerID = NodeID(derived(documentID.rawValue, "starter.\(label).header"))
        let mainID = NodeID(derived(documentID.rawValue, "starter.\(label).main"))
        let footerID = NodeID(derived(documentID.rawValue, "starter.\(label).footer"))
        let titleID = NodeID(derived(documentID.rawValue, "starter.\(label).title"))
        let bodyID = NodeID(derived(documentID.rawValue, "starter.\(label).body"))
        let footerTextID = NodeID(derived(documentID.rawValue, "starter.\(label).footer-text"))

        let nodes = [
            DocumentNode(
                id: rootID, kind: .frame, name: "Root", parent: .page(pageID),
                childIDs: [headerID, mainID, footerID]
            ),
            semanticSection(
                id: headerID, name: "Header", parent: rootID, child: titleID,
                element: .header, y: 40, height: 160
            ),
            textNode(
                id: titleID, name: "Site title", parent: headerID, text: title,
                element: .h1, size: 32, lineHeight: 38
            ),
            semanticSection(
                id: mainID, name: "Main", parent: rootID, child: bodyID,
                element: .main, y: 224, height: 400
            ),
            textNode(
                id: bodyID, name: "Introduction", parent: mainID, text: body,
                element: .p, size: 18, lineHeight: 26
            ),
            semanticSection(
                id: footerID, name: "Footer", parent: rootID, child: footerTextID,
                element: .footer, y: 648, height: 140
            ),
            textNode(
                id: footerTextID, name: "Footer text", parent: footerID, text: footer,
                element: .p, size: 14, lineHeight: 20
            ),
        ]
        return DocumentPage(
            id: pageID, name: name, route: PageRoute(rawValue: route), role: role,
            provenance: .template, rootNodeIDs: [rootID], nodes: nodes
        )
    }

    private static func semanticSection(
        id: NodeID,
        name: String,
        parent: NodeID,
        child: NodeID,
        element: SemanticHTMLElement,
        y: Double,
        height: Double
    ) -> DocumentNode {
        var properties = geometryProperties(id: id, x: 120, y: y, width: 1_200, height: height)
        properties += [
            property(id, "layout.container.kind", .string("section"), .defaulted),
            property(id, "layout.padding", .number(48), .defaulted),
            property(id, "layout.axis", .string("vertical"), .defaulted),
            property(id, "style.fill", .string("surface"), .defaulted),
            property(id, "style.border", .string("subtle"), .defaulted),
            property(id, CanonicalSemanticElement.key, .string(element.rawValue), .authored),
        ]
        for (breakpoint, x, width) in [
            (ResponsiveBreakpoint.tablet, 48.0, 672.0),
            (ResponsiveBreakpoint.mobile, 24.0, 342.0),
        ] {
            properties.append(property(
                id, ResponsiveGeometryResolver.key(.x, breakpoint: breakpoint), .number(x), .defaulted
            ))
            properties.append(property(
                id, ResponsiveGeometryResolver.key(.width, breakpoint: breakpoint), .number(width), .defaulted
            ))
        }
        return DocumentNode(
            id: id, kind: .section, name: name, parent: .node(parent),
            childIDs: [child], properties: properties
        )
    }

    private static func textNode(
        id: NodeID,
        name: String,
        parent: NodeID,
        text: String,
        element: SemanticHTMLElement,
        size: Double,
        lineHeight: Double
    ) -> DocumentNode {
        var properties = geometryProperties(id: id, x: 0, y: 0, width: 240, height: lineHeight * 2)
        properties += [
            property(id, "content.text", .string(text), .defaulted),
            property(id, "style.fill", .string("text-placeholder"), .defaulted),
            property(id, "style.border", .string("none"), .defaulted),
            property(id, CanonicalTypography.namespace + "family", .string(CanonicalTypography.defaultFamily), .defaulted),
            property(id, CanonicalTypography.namespace + "weight", .string(CanonicalFontWeight.regular.rawValue), .defaulted),
            property(id, CanonicalTypography.namespace + "size", .number(size), .defaulted),
            property(id, CanonicalTypography.namespace + "lineHeight", .number(lineHeight), .defaulted),
            property(id, CanonicalTypography.namespace + "tracking", .number(0), .defaulted),
            property(id, CanonicalTypography.namespace + "alignment", .string(CanonicalTextAlignment.leading.rawValue), .defaulted),
            property(id, CanonicalSemanticElement.key, .string(element.rawValue), .authored),
        ]
        return DocumentNode(id: id, kind: .text, name: name, parent: .node(parent), properties: properties)
    }

    private static func geometryProperties(
        id: NodeID, x: Double, y: Double, width: Double, height: Double
    ) -> [NodeProperty] {
        [
            property(id, "layout.x", .number(x), .defaulted),
            property(id, "layout.y", .number(y), .defaulted),
            property(id, "layout.width", .number(width), .defaulted),
            property(id, "layout.height", .number(height), .defaulted),
        ]
    }

    private static func property(
        _ nodeID: NodeID,
        _ key: String,
        _ value: PropertyValue,
        _ origin: PropertyOrigin
    ) -> NodeProperty {
        NodeProperty(
            id: PropertyID(derived(nodeID.rawValue, key)),
            key: PropertyKey(rawValue: key), value: value, origin: origin
        )
    }

    private static func derived(_ namespace: UUID, _ label: String) -> UUID {
        DocumentPage.deterministicUUID(namespace: namespace, label: label)
    }
}

enum ModelValidationError: Error, Equatable, LocalizedError {
    case invalidWebsiteMetadata
    /// OD-035 / SF-1001: a collection breaks a rule in `CanonicalCollections.issues`.
    case invalidCollections
    /// OD-038 / SF-1007: the site languages break a rule in `CanonicalLocalization.issues`.
    case invalidLocalization
    /// OD-038 / SF-1007: a translation breaks a rule in `CanonicalTranslations.validate`.
    case invalidTranslation
    /// OD-033: malformed variant axes, values, combinations, overrides or choices.
    case invalidComponentVariants
    /// SF-0605: malformed container name or container-query rule; SF-0606:
    /// malformed responsive-audit suppression.
    case invalidContainerQueryState
    /// OD-040 / SF-1103: malformed motion (transition or reveal-on-scroll) data.
    case invalidMotionState
    /// OD-039 / SF-1101: malformed event graph (interactions or start hidden).
    case invalidInteractionGraphState
    /// OD-039 / SF-1106: malformed page variables or visibility condition.
    case invalidRuntimeState
    /// OD-039 / SF-1105: malformed overlay data, or an overlay on the page Root.
    case invalidOverlayState
    /// OD-033: an authored variant would make the component invalid.
    case componentVariantResolvesInvalid
    case invalidProjectPreferences
    case componentTextIntentWouldBeLost
    case componentVisibilityIntentWouldBeLost
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
    case invalidSemanticElementState
    case invalidAccessibilityMetadataState
    case invalidResponsiveGeometryState
    case invalidResponsiveContainerState
    case invalidResponsiveVisibilityState
    case invalidFluidValueState
    case invalidIsolationRootState
    case invalidPositioningState
    case invalidReusableStyleState
    case invalidInteractionStyleState
    case duplicateAssetID
    case duplicateAssetResourceID
    case duplicateAssetContent
    case invalidImageAsset
    case invalidFontAsset
    case invalidMediaAsset
    case invalidMediaPlayback
    case invalidImageReference
    case invalidColorToken
    case invalidSizingConstraints
    case invalidComponentReference
    case invalidComponentUsageNotes
    case componentDependencyCycle
    case componentNestingTooDeep
    case componentExpansionTooLarge
    case componentSlotRuleBroken
    case componentSlotContentWouldBeLost

    var errorDescription: String? {
        switch self {
        case .componentTextIntentWouldBeLost: "This text property has authored instance values. Reset those values or detach the affected instances before removing its source or binding."
        case .componentVisibilityIntentWouldBeLost: "This visibility property has authored instance values. Reset them or detach affected instances before removing its source or binding."
        case .revisionNotIncrementable: "The document revision cannot accept another transaction."
        case .invalidComponentUsageNotes:
            "Enter up to \(CanonicalComponentUsageNotes.maximumBytes) UTF-8 bytes of plain text. Line breaks and tabs are allowed."
        case .invalidComponentReference: "The component reference is malformed or belongs to an incompatible object."
        case .invalidComponentVariants: "A component's variants must have 1 to \(CanonicalComponentVariants.maximumAxes) named properties with 2 to \(CanonicalComponentVariants.maximumValuesPerAxis) uniquely named values each, at most \(CanonicalComponentVariants.maximumCombinations) combinations, and overrides only for supported settings."
        case .invalidContainerQueryState: "A container query needs a container name of lowercase letters, digits and hyphens, a width range in whole points and at least one supported setting. Width and height can change only on fixed-size objects inside a Frame. Suppressed responsive findings must be known kinds."
        case .componentVariantResolvesInvalid: "One of this component's variants would contain an invalid setting. Change or reset the variant's value."
        case .componentSlotRuleBroken: "A slot's contents must follow its rules for allowed object types and number of items."
        case .componentSlotContentWouldBeLost: "This copy has its own slot contents. Use the default contents or detach it before linking it to a different component."
        case .componentDependencyCycle: "A component cannot contain itself, directly or through other components."
        case .componentNestingTooDeep: "Components can be nested up to \(CanonicalComponentGraph.maximumNestingDepth) levels."
        case .componentExpansionTooLarge: "A component cannot expand to more than \(ComponentGraphViolation.objectLimitText) objects."
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
        case .invalidIsolationRootState: "The document contains an invalid canvas isolation root."
        case .invalidPositioningState: "The document contains invalid positioning values."
        case .invalidReusableStyleState: "The document contains invalid reusable-style data."
        case .invalidInteractionStyleState: "The document contains invalid state-style data."
        case .invalidMotionState: "The document contains invalid motion data."
        case .invalidInteractionGraphState: "The document contains invalid interaction data."
        case .invalidRuntimeState: "The document contains invalid page variable or visibility data."
        case .invalidOverlayState: "The document contains invalid overlay data."
        case .invalidBoxStyleState: "The document contains an invalid canonical border, radius, or shadow state."
        case .invalidTypographyState: "The document contains invalid canonical typography state."
        case .invalidSemanticElementState: "The document contains an invalid canonical semantic HTML element state."
        case .invalidAccessibilityMetadataState: "The document contains invalid canonical accessibility metadata."
        case .invalidResponsiveGeometryState: "The document contains invalid responsive geometry state."
        case .invalidResponsiveContainerState: "The document contains invalid responsive container-layout state."
        case .invalidResponsiveVisibilityState: "The document contains invalid responsive visibility state."
        case .invalidFluidValueState: "The document contains an invalid canonical fluid responsive value."
        case .duplicateAssetID: "Image asset identifiers must be unique."
        case .duplicateAssetResourceID: "Each image asset must own one stable project resource identity."
        case .duplicateAssetContent: "Duplicate image bytes must resolve to the existing asset identity."
        case .invalidImageAsset: "The document contains invalid image asset metadata."
        case .invalidFontAsset: "The project contains invalid font metadata: each face needs a valid family name (not System), a weight from 100 to 900 in steps of 100, valid file facts, and a unique family, weight and style."
        case .invalidMediaAsset: "The project contains invalid video or audio metadata: each file needs a name, valid file facts, a unique identity and bytes, and a captions language must be a tag such as en or pt-BR."
        case .invalidMediaPlayback: "An Image's video or audio must be a video or audio file in the project; captions are for video only, and only muted video may start by itself."
        case .invalidImageReference: "An Image node must reference an existing canonical image asset."
        case .invalidWebsiteMetadata: "Website metadata must contain valid values and unique existing page identities. A site address must be an https address without a trailing slash, query or fragment. \(CustomCodeBlock.invalidExplanation)"
        case .invalidLocalization: "Site languages need valid unique codes and names, one existing default, fallbacks that end at the default, and addresses no page already uses."
        case .invalidTranslation: "Translations need a language other than the default, a value the element can show (text, alternative text or an existing image) of limited size, and no control characters."
        case .invalidCollections: "Collections need valid unique names and addresses, valid field names and matching item values; published items need every required field."
        case .invalidProjectPreferences: "Project preferences must use a supported version and finite values; a project with nothing set stores no preferences."
        case .invalidColorToken: "The project contains invalid local color token state."
        case .invalidSizingConstraints: "The project contains an invalid sizing mode or constraint."
        }
    }
}

enum CanonicalFluidValueNamespaceValidator {
    static func validate(_ node: DocumentNode) throws {
        let properties = node.properties.filter {
            $0.key.rawValue.hasPrefix(CanonicalFluidValueCodec.namespace + ".")
        }
        guard !properties.isEmpty else { return }
        var targets = Set<FluidValueTarget>()
        for property in properties {
            let suffix = String(property.key.rawValue.dropFirst(CanonicalFluidValueCodec.namespace.count + 1))
            guard let target = FluidValueTarget(rawValue: suffix), target.supports(node.kind),
                  targets.insert(target).inserted,
                  case .string(let raw) = property.value,
                  (try? CanonicalFluidValueCodec.decode(raw, target: target)) != nil else {
                throw ModelValidationError.invalidFluidValueState
            }
        }
        if node.kind.isTextual, (targets.contains(.fontSize) || targets.contains(.lineHeight)) {
            guard let fixed = CanonicalTypography.resolved(for: node) else {
                throw ModelValidationError.invalidFluidValueState
            }
            for width in [CanonicalFluidValue.lowerViewport, CanonicalFluidValue.preferredViewport,
                          CanonicalFluidValue.upperViewport] {
                let size = CanonicalFluidValueCodec.resolved(.fontSize, node: node, viewportWidth: width) ?? fixed.size
                let lineHeight = CanonicalFluidValueCodec.resolved(.lineHeight, node: node, viewportWidth: width) ?? fixed.lineHeight
                guard CanonicalTypography(family: fixed.family, weight: fixed.weight, size: size,
                    lineHeight: lineHeight, tracking: fixed.tracking, alignment: fixed.alignment).isValid else {
                    throw ModelValidationError.invalidFluidValueState
                }
            }
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
    private static let supportedKinds: Set<NodeKind> = [.frame, .text, .section, .stack, .grid, .image, .button, .link, .component]

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

/// SF-0605 (ADR-0031): container queries. A Frame, Section, Stack or Grid
/// becomes a named query container with `responsive.query.v1.container` =
/// name (lowercase letters, digits and hyphens, starting with a letter, up to
/// 32). Any object may carry ordered rules: `responsive.query.v1.rules` =
/// comma list of rule IDs; per rule optional `.container` (a name; absent =
/// the nearest container), optional `.minWidth` / `.maxWidth` (whole points,
/// inclusive, at least one) and one or more `.set.<key>` values for the
/// queryable settings. Omitted means "no rule"; there are no defaulted values.
enum ContainerQueryRuleIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "container-query-rule"
}
typealias ContainerQueryRuleID = StableIdentifier<ContainerQueryRuleIdentifierDomain>

struct CanonicalContainerQueryRule: Equatable, Sendable {
    let id: ContainerQueryRuleID
    /// nil: the nearest active container.
    let container: String?
    let minWidth: Double?
    let maxWidth: Double?
    /// The settings this rule applies, sorted by key.
    let values: [(key: String, property: NodeProperty)]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.container == rhs.container && lhs.minWidth == rhs.minWidth && lhs.maxWidth == rhs.maxWidth
            && lhs.values.map(\.key) == rhs.values.map(\.key) && lhs.values.map(\.property) == rhs.values.map(\.property)
    }

    func matches(width: Double) -> Bool {
        (minWidth.map { width >= $0 } ?? true) && (maxWidth.map { width <= $0 } ?? true)
    }

    /// "400–799 pt", "at least 400 pt", "up to 799 pt".
    var rangeDescription: String {
        func points(_ value: Double) -> String { "\(Int(value)) pt" }
        switch (minWidth, maxWidth) {
        case (let min?, let max?): return "\(Int(min))–\(points(max))"
        case (let min?, nil): return "at least \(points(min))"
        case (nil, let max?): return "up to \(points(max))"
        case (nil, nil): return "any width"
        }
    }
}

enum CanonicalContainerQueries {
    static let namespace = "responsive.query.v1."
    static let containerKey = namespace + "container"
    static let rulesKey = namespace + "rules"
    static let rulePrefix = namespace + "rule."
    /// The document schema that introduced container queries.
    static let documentSchema = 27
    static let maximumRulesPerNode = 8
    static let maximumWidth = 100_000.0
    static let containerKinds: Set<NodeKind> = [.frame, .section, .stack, .grid]
    /// SF-0605-001: the settings a rule may change. Each has one canvas
    /// meaning and one CSS declaration, so canvas, Preview and export agree.
    static let queryableKeys: [String] = [
        "hidden", "style.opacity", CanonicalTypography.namespace + "size", CanonicalTypography.namespace + "lineHeight",
        "layout.width", "layout.height",
    ]

    static func ruleKey(_ id: ContainerQueryRuleID, _ field: String) -> String { rulePrefix + id.description + "." + field }
    static func setKey(_ id: ContainerQueryRuleID, _ key: String) -> String { ruleKey(id, "set." + key) }

    static func isValidName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, (1...32).contains(name.unicodeScalars.count),
              ("a"..."z").contains(first) else { return false }
        return name.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    static func containerName(of node: DocumentNode) -> String? {
        guard case .string(let name)? = node.insertionProperty(containerKey)?.value else { return nil }
        return name
    }

    /// A named container acts as one only when its width never depends on its
    /// contents (no Hug width at any breakpoint), like CSS inline-size
    /// containment; otherwise the defined fallback applies: it is skipped.
    static func isActiveContainer(_ node: DocumentNode) -> Bool {
        containerName(of: node) != nil && hasIndependentContainerWidth(node)
    }

    static func hasIndependentContainerWidth(_ node: DocumentNode) -> Bool {
        ResponsiveBreakpoint.allCases.allSatisfy {
            CanonicalSizingConstraints.effectiveMode(.width, node: node, breakpoint: $0, width: nil) != .hug
        }
    }

    static func hasRules(_ node: DocumentNode) -> Bool { node.insertionProperty(rulesKey) != nil }

    /// A value a rule may set on `node`: the right type and range, text sizes
    /// only on text, and width or height only on a fixed-size object that a
    /// Frame (or the page) places, so no other object moves because of it.
    static func accepts(_ key: String, value: PropertyValue, on node: DocumentNode, parent: DocumentNode?) -> Bool {
        switch (key, value) {
        case ("hidden", .boolean): return true
        case ("style.opacity", .number(let number)): return number.isFinite && (0...1).contains(number)
        // A fluid text size or line height would win over the rule on the
        // canvas but not in CSS, so the two are not combined (SF-0605-003).
        case (CanonicalTypography.namespace + "size", .number(let number)):
            return node.kind.isTextual && number.isFinite && (1...1_000).contains(number)
                && CanonicalFluidValueCodec.value(for: .fontSize, node: node) == nil
        case (CanonicalTypography.namespace + "lineHeight", .number(let number)):
            return node.kind.isTextual && number.isFinite && (1...2_000).contains(number)
                && CanonicalFluidValueCodec.value(for: .lineHeight, node: node) == nil
        case ("layout.width", .number(let number)), ("layout.height", .number(let number)):
            let dimension: SizingDimension = key == "layout.width" ? .width : .height
            let target: FluidValueTarget = key == "layout.width" ? .width : .height
            return number.isFinite && (1...maximumWidth).contains(number)
                && (parent == nil || parent?.kind == .frame)
                && CanonicalFluidValueCodec.value(for: target, node: node) == nil
                && ResponsiveBreakpoint.allCases.allSatisfy {
                    CanonicalSizingConstraints.effectiveMode(dimension, node: node, breakpoint: $0, width: nil) == .fixed
                }
        default: return false
        }
    }

    /// The node's rules in order. Strict: partial, duplicated, non-canonical
    /// or out-of-range data throws.
    static func rules(on node: DocumentNode) throws -> [CanonicalContainerQueryRule] {
        let invalid = ModelValidationError.invalidContainerQueryState
        guard case .string(let list)? = node.insertionProperty(rulesKey)?.value else {
            guard !node.properties.contains(where: { $0.key.rawValue.hasPrefix(rulePrefix) }) else { throw invalid }
            return []
        }
        let parts = list.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let ids = parts.compactMap(ContainerQueryRuleID.init(uuidString:))
        guard !parts.isEmpty, parts.count <= maximumRulesPerNode, ids.count == parts.count,
              zip(ids, parts).allSatisfy({ $0.description == $1 }), Set(ids).count == ids.count else { throw invalid }
        var owned: [String: NodeProperty] = [:]
        for property in node.properties where property.key.rawValue.hasPrefix(rulePrefix) {
            guard property.origin == .authored, owned.updateValue(property, forKey: property.key.rawValue) == nil else { throw invalid }
        }
        var seen = Set<String>()
        var result: [CanonicalContainerQueryRule] = []
        for id in ids {
            func number(_ field: String) throws -> Double? {
                let key = ruleKey(id, field)
                guard let property = owned[key] else { return nil }
                seen.insert(key)
                guard case .number(let value) = property.value, value.isFinite, value.rounded() == value,
                      (0...maximumWidth).contains(value) else { throw invalid }
                return value
            }
            let minWidth = try number("minWidth"), maxWidth = try number("maxWidth")
            guard minWidth != nil || maxWidth != nil, (minWidth ?? 0) <= (maxWidth ?? maximumWidth) else { throw invalid }
            var container: String?
            if let property = owned[ruleKey(id, "container")] {
                seen.insert(ruleKey(id, "container"))
                guard case .string(let name) = property.value, isValidName(name) else { throw invalid }
                container = name
            }
            let setPrefix = ruleKey(id, "set.")
            var values: [(key: String, property: NodeProperty)] = []
            for (key, property) in owned where key.hasPrefix(setPrefix) {
                let target = String(key.dropFirst(setPrefix.count))
                guard queryableKeys.contains(target) else { throw invalid }
                seen.insert(key)
                values.append((target, property))
            }
            guard !values.isEmpty else { throw invalid }
            values.sort { $0.key < $1.key }
            result.append(.init(id: id, container: container, minWidth: minWidth, maxWidth: maxWidth, values: values))
        }
        guard seen == Set(owned.keys) else { throw invalid }
        return result
    }

    /// SF-0605-001/004: per-node rules. Unknown container names are valid
    /// intent (the container may be renamed or come back); they are reported,
    /// not rejected.
    static func validate(_ node: DocumentNode, parent: DocumentNode?) throws {
        let invalid = ModelValidationError.invalidContainerQueryState
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix(namespace) }
        guard !owned.isEmpty else { return }
        for property in owned {
            let key = property.key.rawValue
            guard key == containerKey || key == rulesKey || key.hasPrefix(rulePrefix) else { throw invalid }
        }
        if let property = node.insertionProperty(containerKey) {
            guard containerKinds.contains(node.kind), property.origin == .authored,
                  case .string(let name) = property.value, isValidName(name) else { throw invalid }
        }
        for rule in try rules(on: node) {
            for value in rule.values {
                guard accepts(value.key, value: value.property.value, on: node, parent: parent) else { throw invalid }
            }
        }
    }
}

/// SF-0606-001/004 (ADR-0032): suppressed responsive-audit findings. An
/// object stores the kinds of finding the user marked intentional for it, as
/// `responsive.audit.v1.suppressed` = sorted, comma-separated kinds. Absent
/// means nothing is suppressed. Introduced with document schema 27.
enum CanonicalResponsiveAuditSuppression {
    static let namespace = "responsive.audit.v1."
    static let suppressedKey = namespace + "suppressed"
    static let kinds = ["collision", "overflow", "tap-target", "truncation", "unreachable-override"]

    static func suppressedKinds(of node: DocumentNode) -> Set<String> {
        guard case .string(let raw)? = node.insertionProperty(suppressedKey)?.value else { return [] }
        return Set(raw.split(separator: ",").map(String.init))
    }

    static func encoded(_ kinds: Set<String>) -> String? {
        kinds.isEmpty ? nil : kinds.sorted().joined(separator: ",")
    }

    static func validate(_ node: DocumentNode) throws {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix(namespace) }
        guard !owned.isEmpty else { return }
        guard owned.count == 1, let property = owned.first, property.key.rawValue == suppressedKey, property.origin == .authored,
              case .string(let raw) = property.value else { throw ModelValidationError.invalidContainerQueryState }
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts == parts.sorted(), Set(parts).count == parts.count,
              parts.allSatisfy(kinds.contains) else { throw ModelValidationError.invalidContainerQueryState }
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
        guard [.frame, .text, .section, .stack, .grid, .image, .button, .link, .component].contains(node.kind) else {
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
    private static let supportedKinds: Set<NodeKind> = [.frame, .section, .stack, .grid, .button]
    private static let borderKeys: Set<String> = [
        "border.width", "border.style", "border.color.red", "border.color.green",
        "border.color.blue", "border.color.alpha",
    ]
    private static let shadowKeys: Set<String> = [
        "shadow.offsetX", "shadow.offsetY", "shadow.blur", "shadow.spread",
        "shadow.color.red", "shadow.color.green", "shadow.color.blue", "shadow.color.alpha",
    ]
    private static let shadowEnabledKey = "shadow.enabled"
    private static let radiusKey = "radius.uniform"
    private static let paddingKey = "padding.uniform"
    private static let clipKey = "clip.content"
    private static let contentBoxKinds: Set<NodeKind> = [.frame, .section]

    static func validate(_ node: DocumentNode) throws {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix(root) }
        guard !owned.isEmpty else { return }
        guard supportedKinds.contains(node.kind) else { throw ModelValidationError.invalidBoxStyleState }
        let suffixes = owned.map { String($0.key.rawValue.dropFirst(root.count)) }
        guard Set(suffixes).count == suffixes.count else { throw ModelValidationError.invalidBoxStyleState }
        let allowed = borderKeys.union(shadowKeys).union([shadowEnabledKey, radiusKey, paddingKey, clipKey])
        guard Set(suffixes).isSubset(of: allowed) else { throw ModelValidationError.invalidBoxStyleState }
        let values = Dictionary(uniqueKeysWithValues: owned.map { (String($0.key.rawValue.dropFirst(root.count)), $0.value) })
        if !borderKeys.isDisjoint(with: suffixes) {
            guard borderKeys.isSubset(of: suffixes), case .number(let width)? = values["border.width"],
                  width.isFinite, width >= 0, width <= 100, case .string(let style)? = values["border.style"],
                  ["solid", "dashed", "dotted"].contains(style) else { throw ModelValidationError.invalidBoxStyleState }
            try validateColor("border.color", values: values)
        }
        if let value = values[radiusKey] {
            guard case .number(let radius) = value, radius.isFinite, (0...10_000).contains(radius) else { throw ModelValidationError.invalidBoxStyleState }
        }
        if let value = values[paddingKey] {
            guard contentBoxKinds.contains(node.kind), case .number(let padding) = value,
                  padding.isFinite, (0...10_000).contains(padding) else { throw ModelValidationError.invalidBoxStyleState }
        }
        if let value = values[clipKey] {
            guard contentBoxKinds.contains(node.kind), case .boolean = value else { throw ModelValidationError.invalidBoxStyleState }
        }
        if !shadowKeys.isDisjoint(with: suffixes) || suffixes.contains(shadowEnabledKey) {
            guard shadowKeys.isSubset(of: suffixes) else { throw ModelValidationError.invalidBoxStyleState }
            if let value = values[shadowEnabledKey] {
                guard contentBoxKinds.contains(node.kind), case .boolean = value else { throw ModelValidationError.invalidBoxStyleState }
            }
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
        guard [.text, .button, .link].contains(node.kind) else { throw ModelValidationError.invalidTypographyState }
        let suffixes = owned.map { String($0.key.rawValue.dropFirst(root.count)) }
        let allowed: Set<String> = Set(["family", "weight", "size", "lineHeight", "tracking", "alignment"])
            .union(CanonicalTextForeground.channels.map { "foreground." + $0 })
        guard Set(suffixes).count == suffixes.count, Set(suffixes).isSubset(of: allowed) else {
            throw ModelValidationError.invalidTypographyState
        }
        let foregroundKeys = owned.filter { $0.key.rawValue.hasPrefix(CanonicalTextForeground.prefix) }
        guard foregroundKeys.isEmpty ||
            (foregroundKeys.count == 4 && CanonicalTextForeground.literal(for: node) != nil) else {
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

enum CanonicalSemanticElementValidator {
    static func validate(_ node: DocumentNode) throws {
        let owned = node.properties.filter { $0.key.rawValue == CanonicalSemanticElement.key }
        guard owned.count <= 1 else { throw ModelValidationError.invalidSemanticElementState }
        guard let property = owned.first else { return }
        guard property.origin == .authored,
              case .string(let raw) = property.value,
              let element = SemanticHTMLElement(rawValue: raw),
              CanonicalSemanticElement.supportedElements(for: node.kind).contains(element) else {
            throw ModelValidationError.invalidSemanticElementState
        }
    }
}

enum CanonicalCSSRuleValidator {
    static func validate(_ node: DocumentNode) throws {
        let owned = node.properties.filter { $0.key.rawValue == CanonicalCSSRule.key }
        guard owned.count <= 1 else { throw ModelValidationError.invalidSemanticElementState }
        guard let property = owned.first else { return }
        guard property.origin == .authored, case .string(let value) = property.value,
              value == CanonicalCSSRule.defaultValue else { throw ModelValidationError.invalidSemanticElementState }
    }
}

enum CanonicalFormFieldValidator {
    static func validate(_ node: DocumentNode) throws {
        let owned = node.properties.filter { [CanonicalFormField.labelKey, CanonicalFormField.nameKey, CanonicalFormField.requiredKey, CanonicalFormField.helpKey, CanonicalFormField.kindKey, CanonicalFormField.optionsKey, CanonicalFormField.maximumLengthKey].contains($0.key.rawValue) }
        guard owned.count == Set(owned.map(\.key)).count else { throw ModelValidationError.invalidSemanticElementState }
        guard !owned.isEmpty else { return }
        guard node.kind == .text else { throw ModelValidationError.invalidSemanticElementState }
        var fieldKind: String?
        var encodedOptions: String?
        var maximumLength: Int?
        for property in owned {
            switch property.key.rawValue {
            case CanonicalFormField.labelKey:
                guard case .string(let value) = property.value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 256 else { throw ModelValidationError.invalidSemanticElementState }
            case CanonicalFormField.nameKey:
                guard case .string(let value) = property.value, value.range(of: "^[A-Za-z][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil else { throw ModelValidationError.invalidSemanticElementState }
            case CanonicalFormField.requiredKey:
                guard case .boolean = property.value else { throw ModelValidationError.invalidSemanticElementState }
            case CanonicalFormField.helpKey:
                guard case .string(let value) = property.value, value.count <= 512 else { throw ModelValidationError.invalidSemanticElementState }
            case CanonicalFormField.kindKey:
                guard case .string(let value) = property.value, ["text", "email", "textarea", "checkbox", "select", "submit"].contains(value) else { throw ModelValidationError.invalidSemanticElementState }
                fieldKind = value
            case CanonicalFormField.optionsKey:
                guard case .string(let value) = property.value else { throw ModelValidationError.invalidSemanticElementState }
                encodedOptions = value
            case CanonicalFormField.maximumLengthKey:
                guard case .number(let value) = property.value, value.isFinite,
                      value.rounded() == value,
                      (Double(CanonicalFormField.minimumMaximumLength)...Double(CanonicalFormField.maximumMaximumLength)).contains(value) else {
                    throw ModelValidationError.invalidSemanticElementState
                }
                maximumLength = Int(value)
            default: break
            }
        }
        guard let fieldKind else { throw ModelValidationError.invalidSemanticElementState }
        if fieldKind == "select" {
            guard let encodedOptions else { throw ModelValidationError.invalidSemanticElementState }
            _ = try CanonicalFormSelectOptions.decode(encodedOptions)
        } else if encodedOptions != nil {
            throw ModelValidationError.invalidSemanticElementState
        }
        if maximumLength != nil && !["text", "email", "textarea"].contains(fieldKind) {
            throw ModelValidationError.invalidSemanticElementState
        }
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
    private static let supportedKinds: Set<NodeKind> = [.frame, .section, .stack, .grid, .button]

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
        guard pages.contains(where: { $0.role != .componentDefinition }) else { throw ModelValidationError.emptyPageList }
        guard Set(pages.map(\.id)).count == pages.count else {
            throw ModelValidationError.duplicatePageID
        }
        let websitePages = pages.filter { $0.role != .componentDefinition }
        guard Set(websitePages.map(\.route)).count == websitePages.count else {
            throw ModelValidationError.duplicatePageRoute
        }
        let specialRoles = websitePages.map(\.role).filter { $0 != .standard }
        guard Set(specialRoles).count == specialRoles.count else {
            throw ModelValidationError.duplicatePageRole
        }
        switch creationKind {
        case .template:
            guard templateID != nil else { throw ModelValidationError.invalidCreationProvenance }
        case .blank, .migratedLegacy:
            guard templateID == nil else { throw ModelValidationError.invalidCreationProvenance }
        }

        guard colorTokens.count <= 1_000,
              Set(colorTokens.map(\.id)).count == colorTokens.count,
              Set(colorTokens.map { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }).count == colorTokens.count,
              colorTokens.allSatisfy(\.isValid) else { throw ModelValidationError.invalidColorToken }

        if let websiteMetadata {
            let websitePages = Set(pages.filter { $0.role != .componentDefinition }.map(\.id))
            guard websiteMetadata.isValid,
                  websiteMetadata.pages.count <= websitePages.count,
                  websiteMetadata.pages.allSatisfy({ websitePages.contains($0.pageID) }) else {
                throw ModelValidationError.invalidWebsiteMetadata
            }
        }

        // OD-035 / SF-1001-004: every collection rule (CanonicalCollections.issues).
        guard CanonicalCollections.issues(collections).isEmpty else { throw ModelValidationError.invalidCollections }
        // OD-045 / SF-0805-001: unique identities, bytes and faces; valid values.
        try FontAsset.validate(fontAssets)
        // OD-045 / SF-0803-001: unique identities and bytes; valid values;
        // media identities never collide with image identities.
        try MediaAsset.validate(mediaAssets)
        guard Set(mediaAssets.map(\.id)).isDisjoint(with: imageAssets.map(\.id)) else {
            throw ModelValidationError.invalidMediaAsset
        }
        let mediaByID = Dictionary(uniqueKeysWithValues: mediaAssets.map { ($0.id, $0) })
        // OD-038 / SF-1007-004: languages, fallbacks and language addresses.
        if let localization, !CanonicalLocalization.issues(localization, pages: pages).isEmpty {
            throw ModelValidationError.invalidLocalization
        }
        // OD-038 / SF-1007-004: no translation for the default language.
        try CanonicalTranslations.validate(self)

        if let projectPreferences {
            // SF-0206-001/004: one canonical representation of "nothing set".
            // Value-rule violations stay openable (see isStructurallyValid).
            guard projectPreferences.isStructurallyValid, !projectPreferences.isEmpty else {
                throw ModelValidationError.invalidProjectPreferences
            }
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
        let assetsByID = Dictionary(uniqueKeysWithValues: imageAssets.map { ($0.id, $0) })

        var qrPayloads: [AssetID: String] = [:]
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
            for node in page.nodes {
                try LocalColorTokenBinding.validate(node)
                try CanonicalMediaPlayback.validate(node, media: mediaByID)
                if let qr = try CanonicalQRCode.resolve(node) {
                    guard let image = CanonicalImageStyle.resolve(node), assetsByID[image.assetID]?.contentHash == qr.hash
                    else { throw ModelValidationError.invalidImageReference }
                    guard qrPayloads[image.assetID] == nil || qrPayloads[image.assetID] == qr.payload else { throw ModelValidationError.invalidImageReference }
                    qrPayloads[image.assetID] = qr.payload
                }
            }
        }
        guard pages.flatMap(\.nodes).filter({ CanonicalIsolationRoot.property(in: $0) != nil }).count <= 1 else {
            throw ModelValidationError.invalidIsolationRootState
        }
        _ = try CanonicalReusableStyleIndex(document: self)
        if let violation = CanonicalComponentGraph(document: self).violation { throw violation.validationError }
        try CanonicalComponentSlot.validateContent(in: self)
        let fluidValueIDs = pages.flatMap(\.nodes).flatMap { node in
            FluidValueTarget.allCases.compactMap {
                CanonicalFluidValueCodec.value(for: $0, node: node)?.0.id
            }
        }
        guard Set(fluidValueIDs).count == fluidValueIDs.count else {
            throw ModelValidationError.invalidFluidValueState
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
        guard role == .componentDefinition ? routeValue.isEmpty : (routeValue.first == "/" && !routeValue.contains("?") && !routeValue.contains("#") &&
              !routeValue.contains("//") &&
              (routeValue == "/" || !routeValue.hasSuffix("/"))) else {
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
        if role == .componentDefinition {
            guard rootNodeIDs.count == 1,
                  let root = nodesByID[rootNodeIDs[0]],
                  root.kind.acceptsAuthoredChildren else {
                // OD-034: instances may sit inside a definition; the document-
                // level CanonicalComponentGraph keeps the graph acyclic and bounded.
                throw ModelValidationError.incompatibleChildOwnership
            }
            let exposed = CanonicalComponentText.properties(in: self)
            let visible = CanonicalComponentVisibility.properties(in: self)
            let choices = CanonicalComponentChoice.properties(in: self)
            let media = CanonicalComponentMedia.properties(in: self)
            let actions = CanonicalComponentAction.properties(in: self)
            let slots = CanonicalComponentSlot.properties(in: self)
            let names = exposed.map(\.label) + visible.map(\.label) + choices.map(\.label) + media.map(\.label) + actions.map(\.label) + slots.map(\.label)
            guard names.count <= CanonicalComponentText.maximumProperties,
                  Set(exposed.map(\.id)).count == exposed.count,
                  Set(visible.map(\.id)).count == visible.count,
                  Set(choices.map(\.id)).count == choices.count,
                  Set(media.map(\.id)).count == media.count,
                  Set(actions.map(\.id)).count == actions.count,
                  Set(slots.map(\.id)).count == slots.count,
                  slots.allSatisfy({ !rootNodeIDs.contains($0.sourceNodeID) }),
                  Set(names.map { $0.lowercased() }).count == names.count,
                  visible.allSatisfy({ !rootNodeIDs.contains($0.sourceNodeID) }) else {
                throw ModelValidationError.invalidComponentReference
            }
            try CanonicalComponentSlot.validateDefinition(self)
            try CanonicalComponentOrganization.validateDefinition(self)
            try CanonicalComponentVariants.validateDefinition(self) { variant in
                var variantNodeIDs = Set<NodeID>()
                var variantPropertyIDs = Set<PropertyID>()
                try variant.validate(documentNodeIDs: &variantNodeIDs, documentPropertyIDs: &variantPropertyIDs,
                                     assetIDs: assetIDs, checkpoint: checkpoint)
            }
        }
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
            // OD-018: an instance's children are its supplied slot content;
            // `CanonicalComponentSlot.validateContent` checks their membership.
            guard node.childIDs.isEmpty || node.kind.acceptsAuthoredChildren || node.kind == .component else {
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
            try CanonicalPageChrome.validate(node, in: self)
            try CanonicalComponentReference.validate(node)
            try CanonicalComponentText.validate(node, inDefinition: role == .componentDefinition)
            try CanonicalComponentVisibility.validate(node, inDefinition: role == .componentDefinition)
            try CanonicalComponentChoice.validate(node, inDefinition: role == .componentDefinition)
            try CanonicalComponentMedia.validate(node, inDefinition: role == .componentDefinition)
            try CanonicalComponentAction.validate(node, inDefinition: role == .componentDefinition)
            try CanonicalComponentSlot.validate(node, inDefinition: role == .componentDefinition)
            try CanonicalComponentOrganization.validate(node, inDefinition: role == .componentDefinition)
            try CanonicalComponentUsageNotes.validate(node,
                isDefinitionRoot: role == .componentDefinition && node.id == rootNodeIDs.first)
            try CanonicalComponentVariants.validate(node, inDefinition: role == .componentDefinition,
                isDefinitionRoot: role == .componentDefinition && node.id == rootNodeIDs.first)
            _ = try CanonicalFlowGradient.resolve(node)
            _ = try CanonicalGlassSurface.resolve(node)
            _ = try CanonicalMotion.resolve(node)
            _ = try CanonicalEventGraph.resolve(node)
            try CanonicalPageState.validate(node, isPageRoot: role != .componentDefinition && rootNodeIDs.count == 1
                && node.id == rootNodeIDs[0] && node.parent == .page(id) && node.kind == .frame)
            try CanonicalBoxStyleNamespaceValidator.validate(node)
            try CanonicalSizingNamespaceValidator.validate(node)
            if case .node(let parentID) = node.parent, let parent = nodesByID[parentID],
               [.stack, .grid, .section].contains(parent.kind) {
                for breakpoint in ResponsiveBreakpoint.allCases {
                    guard !(CanonicalSizingConstraints.effectiveMode(.height, node: node, breakpoint: breakpoint, width: nil) == .fill
                        && CanonicalSizingConstraints.effectiveMode(.height, node: parent, breakpoint: breakpoint, width: nil) == .hug)
                    else { throw ModelValidationError.invalidSizingConstraints }
                }
            }
            try CanonicalTypographyNamespaceValidator.validate(node)
            try CanonicalSemanticElementValidator.validate(node)
            try CanonicalAccessibilityMetadata.validate(node)
            try CanonicalCSSRuleValidator.validate(node)
            try CanonicalFormFieldValidator.validate(node)
            if node.properties.contains(where: { $0.key.rawValue.hasPrefix("form.field.v1.") }) {
                guard case .node(let parentID) = node.parent,
                      nodesByID[parentID]?.kind == .form else {
                    throw ModelValidationError.invalidSemanticElementState
                }
            }
            try CanonicalLinkTarget.validate(node)
            try CanonicalImageNamespaceValidator.validate(node)
            try CanonicalImageFill.validate(node)
            try CanonicalTranslations.validate(node, assetIDs: assetIDs)
            try CanonicalResponsiveGeometryNamespaceValidator.validate(node)
            try CanonicalResponsiveContainerNamespaceValidator.validate(node)
            try CanonicalResponsiveVisibilityNamespaceValidator.validate(node)
            try CanonicalFluidValueNamespaceValidator.validate(node)
            try CanonicalResponsiveAuditSuppression.validate(node)
            try CanonicalContainerQueries.validate(node, parent: {
                if case .node(let parentID) = node.parent { return nodesByID[parentID] }
                return nil
            }())
            try CanonicalIsolationRoot.validate(node)
            try CanonicalPositioning.validate(node)
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
            for property in node.properties where property.key.rawValue.hasPrefix(CanonicalComponentMedia.overrideNamespace) {
                guard case .string(let raw) = property.value,
                      let referenced = AssetID(uuidString: raw), assetIDs.contains(referenced) else {
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
        try CanonicalPageFlow.validate(self)
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
        case .frame, .text, .image, .button, .link, .form, .component: break
        }
    }
}

// MARK: - SF-1004 expression language (OD-036, ADR-0070)

/// Value types of the build-time expression language. Any value may also be
/// missing (an empty or absent field); missing is a value state, not a type.
enum SiteExpressionType: String, Codable, CaseIterable, Hashable, Sendable {
    case text, number, boolean, date

    var title: String {
        switch self {
        case .text: "Text"
        case .number: "Number"
        case .boolean: "True or False"
        case .date: "Date"
        }
    }
}

/// A calendar day with no time or zone, so results never depend on the Mac's
/// clock, time zone or locale. Stored as exactly `YYYY-MM-DD`.
struct SiteExpressionDate: Codable, Comparable, Hashable, Sendable {
    static let monthNames = ["January", "February", "March", "April", "May", "June", "July",
                             "August", "September", "October", "November", "December"]
    let year: Int
    let month: Int
    let day: Int

    init?(year: Int, month: Int, day: Int) {
        guard (1...9_999).contains(year), (1...12).contains(month),
              day >= 1, day <= Self.dayCount(month: month, year: year) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Exactly `YYYY-MM-DD` with ASCII digits.
    init?(iso text: String) {
        let bytes = Array(text.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || ($0.element >= 48 && $0.element <= 57) }),
              let year = Int(text.prefix(4)), let month = Int(text.dropFirst(5).prefix(2)),
              let day = Int(text.suffix(2)) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    static func dayCount(month: Int, year: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    var iso: String { "\(Self.padded(year, 4))-\(Self.padded(month, 2))-\(Self.padded(day, 2))" }

    private static func padded(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    static func < (lhs: SiteExpressionDate, rhs: SiteExpressionDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let value = Self(iso: try container.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a YYYY-MM-DD date.")
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }
}

enum SiteExpressionValue: Hashable, Sendable {
    case text(String)
    case number(Double)
    case boolean(Bool)
    case date(SiteExpressionDate)
    case missing

    var type: SiteExpressionType? {
        switch self {
        case .text: .text
        case .number: .number
        case .boolean: .boolean
        case .date: .date
        case .missing: nil
        }
    }

    /// What a binding writes into a page (before HTML escaping). Missing
    /// renders as nothing.
    var renderedText: String {
        switch self {
        case .text(let value): value
        case .number(let value): SiteExpressionEngine.numberText(value)
        case .boolean(let value): value ? "true" : "false"
        case .date(let value): value.iso
        case .missing: ""
        }
    }
}

/// Unicode-scalar offsets into the expression source, for highlighting.
struct SiteExpressionSourceRange: Hashable, Sendable {
    let start: Int
    let end: Int
}

/// SF-1004-004: why an expression cannot be used. Messages name fields,
/// functions and types only, never field values.
struct SiteExpressionError: Error, Equatable, Sendable, LocalizedError {
    enum Category: String, Sendable {
        case empty, syntax, unknownField, unknownFunction, argumentCount, typeMismatch, invalidLiteral, tooLong, tooComplex
    }

    let category: Category
    let range: SiteExpressionSourceRange
    let message: String

    var errorDescription: String? { message }

    var recoverySuggestion: String? {
        switch category {
        case .empty: "Type an expression, for example upper(title)."
        case .syntax: "Check the quotes, parentheses and operators near the highlighted part."
        case .unknownField: "Choose a field from the list of available fields."
        case .unknownFunction: "Choose a function from the list of available functions."
        case .argumentCount, .typeMismatch: "Change the highlighted part so its type matches what the function or operator needs."
        case .invalidLiteral: "Write the highlighted value directly in the form the function lists."
        case .tooLong: "Shorten the expression to at most 2,000 bytes."
        case .tooComplex: "Simplify the expression or split the work across fields."
        }
    }
}

enum SiteExpressionUnaryOperator: String, Hashable, Sendable {
    case negate = "-"
    case not
}

enum SiteExpressionBinaryOperator: String, Hashable, Sendable {
    case add = "+", subtract = "-", multiply = "*", divide = "/"
    case equal = "==", notEqual = "!=", less = "<", lessOrEqual = "<=", greater = ">", greaterOrEqual = ">="
    case and, or
    case fallback = "??"
}

/// The parsed form. Derived from the source text; never stored.
indirect enum SiteExpressionSyntax: Hashable, Sendable {
    case literal(SiteExpressionValue)
    /// A dotted field path such as `author.name`.
    case field(String)
    case unary(SiteExpressionUnaryOperator, SiteExpressionNode)
    case binary(SiteExpressionBinaryOperator, SiteExpressionNode, SiteExpressionNode)
    case call(String, [SiteExpressionNode])
}

struct SiteExpressionNode: Hashable, Sendable {
    let syntax: SiteExpressionSyntax
    let range: SiteExpressionSourceRange
}

/// SF-1004-001: the fields an expression may read, by dotted path, with types.
struct SiteExpressionSchema: Equatable, Sendable {
    var fields: [String: SiteExpressionType]
    init(_ fields: [String: SiteExpressionType] = [:]) { self.fields = fields }
}

/// The values one evaluation reads. Absent paths are missing.
struct SiteExpressionContext: Equatable, Sendable {
    var values: [String: SiteExpressionValue]
    init(_ values: [String: SiteExpressionValue] = [:]) { self.values = values }
    subscript(path path: String) -> SiteExpressionValue { values[path] ?? .missing }
}

/// A type-checked expression. Only `SiteExpressionEngine.check` creates one,
/// so evaluation can rely on argument counts and types.
struct SiteExpressionProgram: Equatable, Sendable {
    let source: String
    let root: SiteExpressionNode
    let resultType: SiteExpressionType
    /// Field paths read, sorted: the dependency list for repair and invalidation.
    let fieldPaths: [String]

    fileprivate init(source: String, root: SiteExpressionNode, resultType: SiteExpressionType, fieldPaths: [String]) {
        self.source = source
        self.root = root
        self.resultType = resultType
        self.fieldPaths = fieldPaths
    }
}

/// SF-1004-003: which rule won while evaluating, in evaluation order.
enum SiteExpressionDecision: Hashable, Sendable {
    case condition(SiteExpressionSourceRange, isTrue: Bool)
    case fallback(SiteExpressionSourceRange, usedFallback: Bool)
    case missingField(String)

    var explanation: String {
        switch self {
        case .condition(_, let isTrue):
            isTrue ? "if(…): the condition is true, so the first result is used."
                : "if(…): the condition is false or missing, so the second result is used."
        case .fallback(_, let usedFallback):
            usedFallback ? "The first value is missing or empty, so the fallback is used."
                : "The first value is present, so the fallback is not used."
        case .missingField(let path): "The field “\(path)” has no value."
        }
    }
}

/// SF-1004-004: a problem found while evaluating. The part that failed is
/// missing; evaluation still finishes.
struct SiteExpressionRuntimeFinding: Hashable, Sendable {
    enum Category: String, Sendable {
        case divisionByZero, numberOutOfRange, textTooLong, invalidDate, invalidNumber
    }

    let category: Category
    let range: SiteExpressionSourceRange

    var message: String {
        switch category {
        case .divisionByZero: "Division by zero; the result is empty."
        case .numberOutOfRange: "The number is too large; the result is empty."
        case .textTooLong: "The text would be longer than 64 KB; the result is empty."
        case .invalidDate: "The text is not a YYYY-MM-DD date; the result is empty."
        case .invalidNumber: "The text is not a number; the result is empty."
        }
    }
}

struct SiteExpressionEvaluation: Equatable, Sendable {
    let value: SiteExpressionValue
    let type: SiteExpressionType
    let decisions: [SiteExpressionDecision]
    let findings: [SiteExpressionRuntimeFinding]
}

/// SF-1004-008: sanitized record of one expression operation. Holds no
/// expression text and no field values.
struct SiteExpressionDiagnostic: Equatable, Sendable {
    let requirementID: String
    let operation: String
    let objectIdentifiers: [String]
    let durationMilliseconds: Int
    let failureCategory: String
}

/// SF-1004-001: an authored expression as stored in the project. Only the
/// source text is authoritative; syntax, types and results are derived.
/// Stored expressions are syntax-checked on decode; field types are checked
/// against the current schema when used, so a deleted field keeps the
/// expression (and its intent) instead of discarding it.
struct SiteExpression: Codable, Hashable, Sendable {
    static let currentVersion = 1
    let version: Int
    let source: String

    /// Nil when the text is not a syntactically valid expression.
    init?(source: String) {
        guard (try? SiteExpressionEngine.parse(source)) != nil else { return nil }
        version = Self.currentVersion
        self.source = source
    }

    func check(_ schema: SiteExpressionSchema) throws -> SiteExpressionProgram {
        try SiteExpressionEngine.check(source, schema: schema)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case version, source }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try values.decode(Int.self, forKey: .version)
        let storedSource = try values.decode(String.self, forKey: .source)
        guard storedVersion == Self.currentVersion, let expression = Self(source: storedSource) else {
            throw DecodingError.dataCorruptedError(forKey: .source, in: values,
                debugDescription: "Unsupported or invalid SiteForge expression.")
        }
        self = expression
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encode(source, forKey: .source)
    }
}

/// OD-036: a small, total, side-effect-free language evaluated at build time.
/// No loops, no user functions, no I/O, no clock: every evaluation finishes
/// after at most `maximumNodes` steps and gives the same result for the same
/// program and context.
enum SiteExpressionEngine {
    static let maximumSourceBytes = 2_000
    static let maximumTokens = 512
    static let maximumNodes = 256
    static let maximumDepth = 32
    static let maximumTextBytes = 65_536
    static let reservedWords: Set<String> = ["and", "or", "not", "true", "false"]
    static let dateStyles = ["iso", "short", "medium", "long", "dayMonthYear", "year"]
    /// For the authoring UI's function list (sorted by name).
    static let functionSignatures = [
        "abs(number) → number",
        "concat(value, …) → text",
        "contains(text, text) → true or false",
        "date(text) → date",
        "day(date) → number",
        "default(value, fallback) → value",
        "endsWith(text, text) → true or false",
        "format(number, decimals) → text",
        "formatDate(date, \"iso\" | \"short\" | \"medium\" | \"long\" | \"dayMonthYear\" | \"year\") → text",
        "if(condition, then, else) → value",
        "isEmpty(value) → true or false",
        "length(text) → number",
        "lower(text) → text",
        "max(number, number) → number",
        "min(number, number) → number",
        "month(date) → number",
        "number(text) → number",
        "replace(text, find, with) → text",
        "round(number[, decimals]) → number",
        "startsWith(text, text) → true or false",
        "text(value) → text",
        "trim(text) → text",
        "truncate(text, characters) → text",
        "upper(text) → text",
        "year(date) → number"
    ]
    static let functionNames: Set<String> = Set(functionSignatures.map { signature in String(signature.prefix { $0 != "(" }) })

    /// Syntax only. Throws `SiteExpressionError`.
    static func parse(_ source: String) throws -> SiteExpressionNode {
        let length = source.unicodeScalars.count
        guard source.utf8.count <= maximumSourceBytes else {
            throw SiteExpressionError(category: .tooLong, range: .init(start: 0, end: length),
                                      message: "The expression is longer than 2,000 bytes.")
        }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SiteExpressionError(category: .empty, range: .init(start: 0, end: length), message: "The expression is empty.")
        }
        var lexer = SiteExpressionLexer(source)
        var parser = SiteExpressionParser(try lexer.tokens())
        return try parser.parseExpression()
    }

    /// Syntax and types against `schema`. Throws `SiteExpressionError`.
    static func check(_ source: String, schema: SiteExpressionSchema) throws -> SiteExpressionProgram {
        let root = try parse(source)
        var fields = Set<String>()
        let resultType = try checkedType(root, schema: schema, fields: &fields)
        return SiteExpressionProgram(source: source, root: root, resultType: resultType, fieldPaths: fields.sorted())
    }

    /// Total: always returns a value (possibly missing) with its provenance.
    static func evaluate(_ program: SiteExpressionProgram, context: SiteExpressionContext) -> SiteExpressionEvaluation {
        var evaluator = SiteExpressionEvaluator(context: context)
        let value = evaluator.evaluate(program.root)
        return SiteExpressionEvaluation(value: value, type: program.resultType,
                                        decisions: evaluator.decisions, findings: evaluator.findings)
    }

    static func diagnostic(_ operation: String, requirementID: String = "SF-1004-008", objectIdentifiers: [String] = [],
                           startedAt start: Date, error: SiteExpressionError? = nil,
                           findings: [SiteExpressionRuntimeFinding] = []) -> SiteExpressionDiagnostic {
        SiteExpressionDiagnostic(requirementID: requirementID, operation: operation,
                                 objectIdentifiers: objectIdentifiers.sorted(),
                                 durationMilliseconds: max(0, Int(Date().timeIntervalSince(start) * 1_000)),
                                 failureCategory: error?.category.rawValue ?? findings.first?.category.rawValue ?? "none")
    }

    /// Integers without a fraction; other numbers in Swift's shortest
    /// round-trip form. Never locale-dependent.
    static func numberText(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value == value.rounded(), Swift.abs(value) < 1e15 { return String(Int64(value)) }
        return String(value)
    }

    private static func checkedType(_ node: SiteExpressionNode, schema: SiteExpressionSchema,
                                    fields: inout Set<String>) throws -> SiteExpressionType {
        switch node.syntax {
        case .literal(let value):
            return value.type ?? .text
        case .field(let path):
            guard let fieldType = schema.fields[path] else {
                throw SiteExpressionError(category: .unknownField, range: node.range, message: "There is no field named “\(path)”.")
            }
            fields.insert(path)
            return fieldType
        case .unary(let op, let operand):
            let operandType = try checkedType(operand, schema: schema, fields: &fields)
            let expected: SiteExpressionType = op == .negate ? .number : .boolean
            try require(operandType, expected, at: operand.range, for: op == .negate ? "-" : "not")
            return expected
        case .binary(let op, let left, let right):
            let leftType = try checkedType(left, schema: schema, fields: &fields)
            let rightType = try checkedType(right, schema: schema, fields: &fields)
            switch op {
            case .add:
                guard leftType == rightType, leftType == .number || leftType == .text else {
                    throw mismatch(node.range, "+ needs two numbers or two texts, not \(leftType.title) and \(rightType.title). Use text(…) to join a number to text.")
                }
                return leftType
            case .subtract, .multiply, .divide:
                try require(leftType, .number, at: left.range, for: op.rawValue)
                try require(rightType, .number, at: right.range, for: op.rawValue)
                return .number
            case .equal, .notEqual:
                guard leftType == rightType else {
                    throw mismatch(node.range, "\(op.rawValue) compares two values of the same type, not \(leftType.title) and \(rightType.title).")
                }
                return .boolean
            case .less, .lessOrEqual, .greater, .greaterOrEqual:
                guard leftType == rightType, leftType != .boolean else {
                    throw mismatch(node.range, "\(op.rawValue) needs two numbers, two dates or two texts, not \(leftType.title) and \(rightType.title).")
                }
                return .boolean
            case .and, .or:
                try require(leftType, .boolean, at: left.range, for: op.rawValue)
                try require(rightType, .boolean, at: right.range, for: op.rawValue)
                return .boolean
            case .fallback:
                guard leftType == rightType else {
                    throw mismatch(node.range, "?? needs a fallback of the same type, not \(leftType.title) and \(rightType.title).")
                }
                return leftType
            }
        case .call(let name, let arguments):
            guard functionNames.contains(name) else {
                throw SiteExpressionError(category: .unknownFunction, range: node.range, message: "There is no function named “\(name)”.")
            }
            var types: [SiteExpressionType] = []
            for argument in arguments { types.append(try checkedType(argument, schema: schema, fields: &fields)) }
            return try functionType(name, arguments, types, at: node.range)
        }
    }

    private static func functionType(_ name: String, _ arguments: [SiteExpressionNode], _ types: [SiteExpressionType],
                                     at range: SiteExpressionSourceRange) throws -> SiteExpressionType {
        func count(_ allowed: ClosedRange<Int>) throws {
            guard allowed.contains(types.count) else {
                let wanted = allowed.lowerBound == allowed.upperBound ? "\(allowed.lowerBound)" : "\(allowed.lowerBound) to \(allowed.upperBound)"
                throw SiteExpressionError(category: .argumentCount, range: range,
                                          message: "\(name)(…) takes \(wanted) values, not \(types.count).")
            }
        }
        func expect(_ expected: [SiteExpressionType]) throws {
            try count(expected.count...expected.count)
            for (index, wanted) in expected.enumerated() where types[index] != wanted {
                throw SiteExpressionError(category: .typeMismatch, range: arguments[index].range,
                                          message: "Value \(index + 1) of \(name)(…) must be \(wanted.title), not \(types[index].title).")
            }
        }
        switch name {
        case "if":
            try count(3...3)
            try require(types[0], .boolean, at: arguments[0].range, for: "The condition of if(…)")
            guard types[1] == types[2] else {
                throw mismatch(range, "Both results of if(…) must have the same type, not \(types[1].title) and \(types[2].title).")
            }
            return types[1]
        case "default":
            try count(2...2)
            guard types[0] == types[1] else {
                throw mismatch(range, "default(…) needs a fallback of the same type, not \(types[0].title) and \(types[1].title).")
            }
            return types[0]
        case "upper", "lower", "trim":
            try expect([.text])
            return .text
        case "length":
            try expect([.text])
            return .number
        case "text":
            try count(1...1)
            return .text
        case "concat":
            try count(1...16)
            return .text
        case "number":
            try expect([.text])
            return .number
        case "round":
            if types.count == 2 {
                try expect([.number, .number])
                try requireWholeNumberLiteral(arguments[1], in: 0...6, function: name)
            } else {
                try expect([.number])
            }
            return .number
        case "format":
            try expect([.number, .number])
            try requireWholeNumberLiteral(arguments[1], in: 0...10, function: name)
            return .text
        case "abs":
            try expect([.number])
            return .number
        case "min", "max":
            try expect([.number, .number])
            return .number
        case "contains", "startsWith", "endsWith":
            try expect([.text, .text])
            return .boolean
        case "replace":
            try expect([.text, .text, .text])
            return .text
        case "truncate":
            try expect([.text, .number])
            try requireWholeNumberLiteral(arguments[1], in: 1...10_000, function: name)
            return .text
        case "isEmpty":
            try count(1...1)
            return .boolean
        case "date":
            try expect([.text])
            if case .literal(.text(let literal)) = arguments[0].syntax, SiteExpressionDate(iso: literal) == nil {
                throw SiteExpressionError(category: .invalidLiteral, range: arguments[0].range,
                                          message: "date(…) needs a real date written as YYYY-MM-DD.")
            }
            return .date
        case "formatDate":
            try expect([.date, .text])
            guard case .literal(.text(let style)) = arguments[1].syntax, dateStyles.contains(style) else {
                throw SiteExpressionError(category: .invalidLiteral, range: arguments[1].range,
                                          message: "The second value of formatDate(…) must be one of: \(dateStyles.joined(separator: ", ")).")
            }
            return .text
        case "year", "month", "day":
            try expect([.date])
            return .number
        default:
            throw SiteExpressionError(category: .unknownFunction, range: range, message: "There is no function named “\(name)”.")
        }
    }

    private static func requireWholeNumberLiteral(_ node: SiteExpressionNode, in bounds: ClosedRange<Int>,
                                                  function name: String) throws {
        guard case .literal(.number(let value)) = node.syntax, value == value.rounded(),
              value >= Double(bounds.lowerBound), value <= Double(bounds.upperBound) else {
            throw SiteExpressionError(category: .invalidLiteral, range: node.range,
                message: "This value of \(name)(…) must be a whole number from \(bounds.lowerBound) to \(bounds.upperBound), written directly.")
        }
    }

    private static func require(_ actual: SiteExpressionType, _ expected: SiteExpressionType,
                                at range: SiteExpressionSourceRange, for operation: String) throws {
        guard actual == expected else {
            throw SiteExpressionError(category: .typeMismatch, range: range,
                                      message: "\(operation) needs \(expected.title), not \(actual.title).")
        }
    }

    private static func mismatch(_ range: SiteExpressionSourceRange, _ message: String) -> SiteExpressionError {
        SiteExpressionError(category: .typeMismatch, range: range, message: message)
    }
}

private enum SiteExpressionToken: Equatable {
    case number(Double)
    case text(String)
    case name(String)
    case symbol(String)
    case end
}

private struct SiteExpressionLexeme {
    let token: SiteExpressionToken
    let range: SiteExpressionSourceRange
}

private struct SiteExpressionLexer {
    let scalars: [Unicode.Scalar]
    var index = 0

    init(_ source: String) { scalars = Array(source.unicodeScalars) }

    mutating func tokens() throws -> [SiteExpressionLexeme] {
        var lexeme = try next()
        var result = [lexeme]
        while lexeme.token != .end {
            if result.count >= SiteExpressionEngine.maximumTokens {
                throw SiteExpressionError(category: .tooComplex, range: lexeme.range,
                    message: "The expression has more than \(SiteExpressionEngine.maximumTokens) parts.")
            }
            lexeme = try next()
            result.append(lexeme)
        }
        return result
    }

    private static func isDigit(_ c: Unicode.Scalar) -> Bool { c.value >= 48 && c.value <= 57 }
    private static func isNameStart(_ c: Unicode.Scalar) -> Bool {
        (c.value >= 65 && c.value <= 90) || (c.value >= 97 && c.value <= 122) || c.value == 95
    }
    private static func isNamePart(_ c: Unicode.Scalar) -> Bool { isNameStart(c) || isDigit(c) }
    private static func isSpace(_ c: Unicode.Scalar) -> Bool { c.value == 32 || c.value == 9 || c.value == 10 || c.value == 13 }

    private func text(_ from: Int, _ to: Int) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[from..<to])
        return String(view)
    }

    private mutating func next() throws -> SiteExpressionLexeme {
        while index < scalars.count, Self.isSpace(scalars[index]) { index += 1 }
        let start = index
        guard index < scalars.count else { return SiteExpressionLexeme(token: .end, range: .init(start: start, end: start)) }
        let c = scalars[index]
        if Self.isDigit(c) { return try number(from: start) }
        if Self.isNameStart(c) {
            index += 1
            while index < scalars.count, Self.isNamePart(scalars[index]) { index += 1 }
            return SiteExpressionLexeme(token: .name(text(start, index)), range: .init(start: start, end: index))
        }
        if c == "\"" { return try string(from: start) }
        if index + 1 < scalars.count {
            let pair = text(index, index + 2)
            if ["==", "!=", "<=", ">=", "&&", "||", "??"].contains(pair) {
                index += 2
                return SiteExpressionLexeme(token: .symbol(pair), range: .init(start: start, end: index))
            }
        }
        if "+-*/<>!(),.".unicodeScalars.contains(c) {
            index += 1
            return SiteExpressionLexeme(token: .symbol(String(Character(c))), range: .init(start: start, end: index))
        }
        throw SiteExpressionError(category: .syntax, range: .init(start: start, end: start + 1),
                                  message: "This character is not part of the expression language.")
    }

    private mutating func number(from start: Int) throws -> SiteExpressionLexeme {
        while index < scalars.count, Self.isDigit(scalars[index]) { index += 1 }
        if index + 1 < scalars.count, scalars[index] == ".", Self.isDigit(scalars[index + 1]) {
            index += 1
            while index < scalars.count, Self.isDigit(scalars[index]) { index += 1 }
        }
        let range = SiteExpressionSourceRange(start: start, end: index)
        if index < scalars.count, Self.isNamePart(scalars[index]) {
            throw SiteExpressionError(category: .syntax, range: .init(start: start, end: index + 1),
                                      message: "A number cannot be followed directly by a letter.")
        }
        guard index - start <= 24, let value = Double(text(start, index)), value.isFinite else {
            throw SiteExpressionError(category: .invalidLiteral, range: range, message: "This number has more than 24 digits.")
        }
        return SiteExpressionLexeme(token: .number(value), range: range)
    }

    private mutating func string(from start: Int) throws -> SiteExpressionLexeme {
        index += 1
        var value = String.UnicodeScalarView()
        while index < scalars.count {
            let c = scalars[index]
            if c == "\"" {
                index += 1
                return SiteExpressionLexeme(token: .text(String(value)), range: .init(start: start, end: index))
            }
            if c.value == 0 {
                throw SiteExpressionError(category: .syntax, range: .init(start: index, end: index + 1),
                                          message: "Text in an expression cannot contain a NUL character.")
            }
            if c == "\\" {
                guard index + 1 < scalars.count else { break }
                let escaped = scalars[index + 1]
                if escaped == "\"" {
                    value.append("\"")
                } else if escaped == "\\" {
                    value.append("\\")
                } else if escaped == "n" {
                    value.append("\n")
                } else if escaped == "t" {
                    value.append("\t")
                } else {
                    throw SiteExpressionError(category: .syntax, range: .init(start: index, end: index + 2),
                                              message: "Only \\\", \\\\, \\n and \\t may follow a backslash in text.")
                }
                index += 2
                continue
            }
            value.append(c)
            index += 1
        }
        throw SiteExpressionError(category: .syntax, range: .init(start: start, end: scalars.count),
                                  message: "This text is missing its closing quote.")
    }
}

/// Precedence, lowest first: or, and, == !=, < <= > >=, ??, + -, * /, unary - not.
private struct SiteExpressionParser {
    let lexemes: [SiteExpressionLexeme]
    var position = 0
    var nodeCount = 0

    init(_ lexemes: [SiteExpressionLexeme]) { self.lexemes = lexemes }

    private var current: SiteExpressionLexeme { lexemes[position] }

    private mutating func advance() -> SiteExpressionLexeme {
        let lexeme = lexemes[position]
        if position < lexemes.count - 1 { position += 1 }
        return lexeme
    }

    private func isSymbol(_ symbol: String) -> Bool { current.token == .symbol(symbol) }

    private func binaryOperator(_ table: [String: SiteExpressionBinaryOperator]) -> SiteExpressionBinaryOperator? {
        switch current.token {
        case .symbol(let spelling), .name(let spelling): return table[spelling]
        default: return nil
        }
    }

    mutating func parseExpression() throws -> SiteExpressionNode {
        let node = try parseOr(depth: 0)
        guard current.token == .end else {
            throw SiteExpressionError(category: .syntax, range: current.range,
                                      message: "Expected an operator or the end of the expression here.")
        }
        return node
    }

    private mutating func make(_ syntax: SiteExpressionSyntax, _ start: Int, _ end: Int) throws -> SiteExpressionNode {
        nodeCount += 1
        let range = SiteExpressionSourceRange(start: start, end: end)
        guard nodeCount <= SiteExpressionEngine.maximumNodes else {
            throw SiteExpressionError(category: .tooComplex, range: range,
                                      message: "The expression has more than \(SiteExpressionEngine.maximumNodes) parts.")
        }
        return SiteExpressionNode(syntax: syntax, range: range)
    }

    private func requireDepth(_ depth: Int) throws {
        guard depth <= SiteExpressionEngine.maximumDepth else {
            throw SiteExpressionError(category: .tooComplex, range: current.range,
                                      message: "The expression is nested more than \(SiteExpressionEngine.maximumDepth) levels deep.")
        }
    }

    private mutating func parseOr(depth: Int) throws -> SiteExpressionNode {
        var left = try parseAnd(depth: depth)
        while let op = binaryOperator(["or": .or, "||": .or]) {
            _ = advance()
            let right = try parseAnd(depth: depth)
            left = try make(.binary(op, left, right), left.range.start, right.range.end)
        }
        return left
    }

    private mutating func parseAnd(depth: Int) throws -> SiteExpressionNode {
        var left = try parseEquality(depth: depth)
        while let op = binaryOperator(["and": .and, "&&": .and]) {
            _ = advance()
            let right = try parseEquality(depth: depth)
            left = try make(.binary(op, left, right), left.range.start, right.range.end)
        }
        return left
    }

    private mutating func parseEquality(depth: Int) throws -> SiteExpressionNode {
        var left = try parseComparison(depth: depth)
        while let op = binaryOperator(["==": .equal, "!=": .notEqual]) {
            _ = advance()
            let right = try parseComparison(depth: depth)
            left = try make(.binary(op, left, right), left.range.start, right.range.end)
        }
        return left
    }

    private mutating func parseComparison(depth: Int) throws -> SiteExpressionNode {
        var left = try parseFallback(depth: depth)
        while let op = binaryOperator(["<": .less, "<=": .lessOrEqual, ">": .greater, ">=": .greaterOrEqual]) {
            _ = advance()
            let right = try parseFallback(depth: depth)
            left = try make(.binary(op, left, right), left.range.start, right.range.end)
        }
        return left
    }

    private mutating func parseFallback(depth: Int) throws -> SiteExpressionNode {
        var left = try parseAdditive(depth: depth)
        while let op = binaryOperator(["??": .fallback]) {
            _ = advance()
            let right = try parseAdditive(depth: depth)
            left = try make(.binary(op, left, right), left.range.start, right.range.end)
        }
        return left
    }

    private mutating func parseAdditive(depth: Int) throws -> SiteExpressionNode {
        var left = try parseMultiplicative(depth: depth)
        while let op = binaryOperator(["+": .add, "-": .subtract]) {
            _ = advance()
            let right = try parseMultiplicative(depth: depth)
            left = try make(.binary(op, left, right), left.range.start, right.range.end)
        }
        return left
    }

    private mutating func parseMultiplicative(depth: Int) throws -> SiteExpressionNode {
        var left = try parseUnary(depth: depth)
        while let op = binaryOperator(["*": .multiply, "/": .divide]) {
            _ = advance()
            let right = try parseUnary(depth: depth)
            left = try make(.binary(op, left, right), left.range.start, right.range.end)
        }
        return left
    }

    private mutating func parseUnary(depth: Int) throws -> SiteExpressionNode {
        let start = current.range.start
        let op: SiteExpressionUnaryOperator?
        if isSymbol("-") {
            op = .negate
        } else if isSymbol("!") || current.token == .name("not") {
            op = .not
        } else {
            op = nil
        }
        guard let op else { return try parsePrimary(depth: depth) }
        _ = advance()
        try requireDepth(depth + 1)
        let operand = try parseUnary(depth: depth + 1)
        return try make(.unary(op, operand), start, operand.range.end)
    }

    private mutating func parsePrimary(depth: Int) throws -> SiteExpressionNode {
        let lexeme = advance()
        switch lexeme.token {
        case .number(let value):
            return try make(.literal(.number(value)), lexeme.range.start, lexeme.range.end)
        case .text(let value):
            return try make(.literal(.text(value)), lexeme.range.start, lexeme.range.end)
        case .name("true"):
            return try make(.literal(.boolean(true)), lexeme.range.start, lexeme.range.end)
        case .name("false"):
            return try make(.literal(.boolean(false)), lexeme.range.start, lexeme.range.end)
        case .name(let name):
            guard !SiteExpressionEngine.reservedWords.contains(name) else {
                throw SiteExpressionError(category: .syntax, range: lexeme.range,
                                          message: "“\(name)” is an operator; a value is expected here.")
            }
            if isSymbol("(") { return try parseCall(name, start: lexeme.range.start, depth: depth) }
            var path = name
            var end = lexeme.range.end
            while isSymbol(".") {
                _ = advance()
                let part = advance()
                guard case .name(let segment) = part.token, !SiteExpressionEngine.reservedWords.contains(segment) else {
                    throw SiteExpressionError(category: .syntax, range: part.range, message: "Expected a field name after the dot.")
                }
                path += "." + segment
                end = part.range.end
            }
            return try make(.field(path), lexeme.range.start, end)
        case .symbol("("):
            try requireDepth(depth + 1)
            let inner = try parseOr(depth: depth + 1)
            let close = advance()
            guard close.token == .symbol(")") else {
                throw SiteExpressionError(category: .syntax, range: close.range, message: "Expected a closing parenthesis here.")
            }
            return SiteExpressionNode(syntax: inner.syntax, range: .init(start: lexeme.range.start, end: close.range.end))
        case .end:
            throw SiteExpressionError(category: .syntax, range: lexeme.range, message: "The expression ends where a value is expected.")
        default:
            throw SiteExpressionError(category: .syntax, range: lexeme.range, message: "Expected a value, a field or a function here.")
        }
    }

    private mutating func parseCall(_ name: String, start: Int, depth: Int) throws -> SiteExpressionNode {
        _ = advance()
        try requireDepth(depth + 1)
        var arguments: [SiteExpressionNode] = []
        if !isSymbol(")") {
            while true {
                arguments.append(try parseOr(depth: depth + 1))
                guard isSymbol(",") else { break }
                _ = advance()
            }
        }
        let close = advance()
        guard close.token == .symbol(")") else {
            throw SiteExpressionError(category: .syntax, range: close.range, message: "Expected a comma or a closing parenthesis here.")
        }
        return try make(.call(name, arguments), start, close.range.end)
    }
}

/// Missing-value rules: text parameters read a missing value as empty text;
/// conditions read it as false; arithmetic, dates and number functions give
/// missing; `==` treats missing and empty text as equal; ordering with a
/// missing side is false.
private struct SiteExpressionEvaluator {
    let context: SiteExpressionContext
    var decisions: [SiteExpressionDecision] = []
    var findings: [SiteExpressionRuntimeFinding] = []

    mutating func evaluate(_ node: SiteExpressionNode) -> SiteExpressionValue {
        switch node.syntax {
        case .literal(let literal):
            return literal
        case .field(let path):
            let fieldValue = context[path: path]
            if fieldValue == .missing, !decisions.contains(.missingField(path)) { decisions.append(.missingField(path)) }
            return fieldValue
        case .unary(let op, let operand):
            let operandValue = evaluate(operand)
            switch op {
            case .negate:
                guard case .number(let number) = operandValue else { return .missing }
                return checkedNumber(-number, at: node.range)
            case .not:
                return .boolean(!Self.truth(operandValue))
            }
        case .binary(let op, let left, let right):
            switch op {
            case .and:
                guard Self.truth(evaluate(left)) else { return .boolean(false) }
                return .boolean(Self.truth(evaluate(right)))
            case .or:
                if Self.truth(evaluate(left)) { return .boolean(true) }
                return .boolean(Self.truth(evaluate(right)))
            case .fallback:
                let first = evaluate(left)
                let usesFallback = Self.isEmpty(first)
                decisions.append(.fallback(node.range, usedFallback: usesFallback))
                return usesFallback ? evaluate(right) : first
            default:
                let leftValue = evaluate(left)
                let rightValue = evaluate(right)
                return binary(op, leftValue, rightValue, at: node.range)
            }
        case .call(let name, let arguments):
            return call(name, arguments, at: node.range)
        }
    }

    private mutating func binary(_ op: SiteExpressionBinaryOperator, _ left: SiteExpressionValue,
                                 _ right: SiteExpressionValue, at range: SiteExpressionSourceRange) -> SiteExpressionValue {
        switch op {
        case .equal:
            return .boolean(Self.equal(left, right))
        case .notEqual:
            return .boolean(!Self.equal(left, right))
        case .less, .lessOrEqual, .greater, .greaterOrEqual:
            guard let order = Self.order(left, right) else { return .boolean(false) }
            switch op {
            case .less: return .boolean(order < 0)
            case .lessOrEqual: return .boolean(order <= 0)
            case .greater: return .boolean(order > 0)
            default: return .boolean(order >= 0)
            }
        case .add:
            switch (left, right) {
            case (.number(let a), .number(let b)): return checkedNumber(a + b, at: range)
            case (.text, _), (_, .text): return checkedText(Self.text(left) + Self.text(right), at: range)
            default: return .missing
            }
        case .subtract, .multiply, .divide:
            guard case .number(let a) = left, case .number(let b) = right else { return .missing }
            if op == .divide, b == 0 {
                findings.append(SiteExpressionRuntimeFinding(category: .divisionByZero, range: range))
                return .missing
            }
            let result = op == .subtract ? a - b : (op == .multiply ? a * b : a / b)
            return checkedNumber(result, at: range)
        case .and, .or, .fallback:
            return .missing
        }
    }

    private mutating func call(_ name: String, _ arguments: [SiteExpressionNode],
                               at range: SiteExpressionSourceRange) -> SiteExpressionValue {
        if name == "if" {
            let isTrue = Self.truth(evaluate(arguments[0]))
            decisions.append(.condition(range, isTrue: isTrue))
            return evaluate(arguments[isTrue ? 1 : 2])
        }
        if name == "default" {
            let first = evaluate(arguments[0])
            let usesFallback = Self.isEmpty(first)
            decisions.append(.fallback(range, usedFallback: usesFallback))
            return usesFallback ? evaluate(arguments[1]) : first
        }
        var values: [SiteExpressionValue] = []
        for argument in arguments { values.append(evaluate(argument)) }
        switch name {
        case "upper":
            return checkedText(Self.text(values[0]).uppercased(), at: range)
        case "lower":
            return checkedText(Self.text(values[0]).lowercased(), at: range)
        case "trim":
            return .text(Self.text(values[0]).trimmingCharacters(in: .whitespacesAndNewlines))
        case "length":
            return .number(Double(Self.text(values[0]).count))
        case "text":
            return .text(values[0].renderedText)
        case "concat":
            return checkedText(values.map(\.renderedText).joined(), at: range)
        case "number":
            let raw = Self.text(values[0]).trimmingCharacters(in: .whitespaces)
            if raw.isEmpty { return .missing }
            guard let parsed = Self.parseNumber(raw) else {
                findings.append(SiteExpressionRuntimeFinding(category: .invalidNumber, range: range))
                return .missing
            }
            return .number(parsed)
        case "round":
            guard case .number(let number) = values[0] else { return .missing }
            let scale = pow(10.0, Double(values.count > 1 ? Self.wholeNumber(values[1]) : 0))
            return checkedNumber((number * scale).rounded(.toNearestOrAwayFromZero) / scale, at: range)
        case "format":
            guard case .number(let number) = values[0] else { return .missing }
            return checkedText(String(format: "%.\(Self.wholeNumber(values[1]))f", number), at: range)
        case "abs":
            guard case .number(let number) = values[0] else { return .missing }
            return .number(Swift.abs(number))
        case "min", "max":
            guard case .number(let a) = values[0], case .number(let b) = values[1] else { return .missing }
            return .number(name == "min" ? Swift.min(a, b) : Swift.max(a, b))
        case "contains", "startsWith", "endsWith":
            let base = Self.text(values[0])
            let part = Self.text(values[1])
            if part.isEmpty { return .boolean(true) }
            if name == "contains" { return .boolean(base.contains(part)) }
            return .boolean(name == "startsWith" ? base.hasPrefix(part) : base.hasSuffix(part))
        case "replace":
            let base = Self.text(values[0])
            let find = Self.text(values[1])
            let replacement = Self.text(values[2])
            guard !find.isEmpty else { return .text(base) }
            let pieces = base.components(separatedBy: find)
            let size = pieces.reduce(0) { $0 + $1.utf8.count } + (pieces.count - 1) * replacement.utf8.count
            guard size <= SiteExpressionEngine.maximumTextBytes else {
                findings.append(SiteExpressionRuntimeFinding(category: .textTooLong, range: range))
                return .missing
            }
            return .text(pieces.joined(separator: replacement))
        case "truncate":
            let base = Self.text(values[0])
            let limit = Self.wholeNumber(values[1])
            guard base.count > limit else { return .text(base) }
            return .text(String(base.prefix(limit)) + "…")
        case "isEmpty":
            return .boolean(Self.isEmpty(values[0]))
        case "date":
            let raw = Self.text(values[0])
            if raw.isEmpty { return .missing }
            guard let date = SiteExpressionDate(iso: raw) else {
                findings.append(SiteExpressionRuntimeFinding(category: .invalidDate, range: range))
                return .missing
            }
            return .date(date)
        case "formatDate":
            guard case .date(let date) = values[0] else { return .missing }
            return .text(Self.formatted(date, style: Self.text(values[1])))
        case "year", "month", "day":
            guard case .date(let date) = values[0] else { return .missing }
            return .number(Double(name == "year" ? date.year : (name == "month" ? date.month : date.day)))
        default:
            return .missing
        }
    }

    private mutating func checkedNumber(_ number: Double, at range: SiteExpressionSourceRange) -> SiteExpressionValue {
        guard number.isFinite else {
            findings.append(SiteExpressionRuntimeFinding(category: .numberOutOfRange, range: range))
            return .missing
        }
        return .number(number == 0 ? 0 : number)
    }

    private mutating func checkedText(_ text: String, at range: SiteExpressionSourceRange) -> SiteExpressionValue {
        guard text.utf8.count <= SiteExpressionEngine.maximumTextBytes else {
            findings.append(SiteExpressionRuntimeFinding(category: .textTooLong, range: range))
            return .missing
        }
        return .text(text)
    }

    static func truth(_ value: SiteExpressionValue) -> Bool { value == .boolean(true) }

    static func isEmpty(_ value: SiteExpressionValue) -> Bool {
        switch value {
        case .missing: return true
        case .text(let text): return text.isEmpty
        default: return false
        }
    }

    static func text(_ value: SiteExpressionValue) -> String {
        if case .text(let text) = value { return text }
        return ""
    }

    static func equal(_ left: SiteExpressionValue, _ right: SiteExpressionValue) -> Bool {
        if left == .missing || right == .missing { return isEmpty(left) && isEmpty(right) }
        return left == right
    }

    static func order(_ left: SiteExpressionValue, _ right: SiteExpressionValue) -> Int? {
        switch (left, right) {
        case (.number(let a), .number(let b)): return a < b ? -1 : (a > b ? 1 : 0)
        case (.date(let a), .date(let b)): return a < b ? -1 : (a > b ? 1 : 0)
        case (.text(let a), .text(let b)): return a < b ? -1 : (a > b ? 1 : 0)
        default: return nil
        }
    }

    static func wholeNumber(_ value: SiteExpressionValue) -> Int {
        guard case .number(let number) = value, number.isFinite else { return 0 }
        return Int(Swift.max(0, Swift.min(10_000, number.rounded())))
    }

    static func isDigits(_ text: Substring) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }

    /// Plain decimal only: optional minus, digits, optional fraction. No
    /// exponent, hex, infinity or NaN spellings.
    static func parseNumber(_ raw: String) -> Double? {
        var body = Substring(raw)
        if body.hasPrefix("-") { body = body.dropFirst() }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard raw.utf8.count <= 24, (1...2).contains(parts.count), parts.allSatisfy(isDigits),
              let value = Double(raw), value.isFinite else { return nil }
        return value
    }

    static func formatted(_ date: SiteExpressionDate, style: String) -> String {
        let month = SiteExpressionDate.monthNames[date.month - 1]
        switch style {
        case "short": return "\(date.month)/\(date.day)/\(date.year)"
        case "medium": return "\(month.prefix(3)) \(date.day), \(date.year)"
        case "long": return "\(month) \(date.day), \(date.year)"
        case "dayMonthYear": return "\(date.day) \(month) \(date.year)"
        case "year": return String(date.year)
        default: return date.iso
        }
    }
}

// MARK: - SF-1007 / SF-1506 site localization (OD-038, ADR-0080)

enum SiteLocaleIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "site-locale"
}

typealias SiteLocaleID = StableIdentifier<SiteLocaleIdentifierDomain>

/// OD-038: the reading direction of one site language.
enum SiteTextDirection: String, Codable, CaseIterable, Sendable {
    case leftToRight, rightToLeft

    var title: String {
        switch self {
        case .leftToRight: "Left to Right"
        case .rightToLeft: "Right to Left"
        }
    }

    /// The HTML `dir` value.
    var htmlValue: String {
        switch self {
        case .leftToRight: "ltr"
        case .rightToLeft: "rtl"
        }
    }

    static let rightToLeftLanguages: Set<String> = [
        "ar", "arc", "ckb", "dv", "fa", "he", "iw", "ks", "ps", "sd", "syr", "ug", "ur", "yi",
    ]
    static let rightToLeftScripts: Set<String> = ["Adlm", "Arab", "Hebr", "Nkoo", "Rohg", "Syrc", "Thaa"]

    /// SF-1007-003: the direction a canonical language tag implies. An explicit
    /// script subtag wins over the language (`az-Arab` is right to left,
    /// `ar-Latn` left to right).
    static func implied(byCode code: String) -> SiteTextDirection {
        let parts = code.split(separator: "-").map(String.init)
        if parts.count > 1, parts[1].count == 4 {
            return rightToLeftScripts.contains(parts[1]) ? .rightToLeft : .leftToRight
        }
        return rightToLeftLanguages.contains(parts.first ?? "") ? .rightToLeft : .leftToRight
    }
}

/// SF-1007-001/004: canonical BCP 47 language tags (language, optional
/// script, optional region, variants). Private-use and extension subtags are
/// not supported.
enum SiteLocaleCode {
    static let maximumBytes = 35

    /// The canonical spelling (`fr-CA`, `zh-Hant-TW`), or `nil` when `raw` is
    /// not a supported tag. Underscores are read as hyphens.
    static func canonical(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-")
        guard !trimmed.isEmpty, trimmed.utf8.count <= maximumBytes,
              trimmed.unicodeScalars.allSatisfy({ $0.isASCII }) else { return nil }
        let parts = trimmed.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        func letters(_ value: String) -> Bool { value.allSatisfy({ $0.isASCII && $0.isLetter }) }
        func digits(_ value: String) -> Bool { value.allSatisfy({ $0.isASCII && $0.isNumber }) }
        func alphanumerics(_ value: String) -> Bool { value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) }
        guard (2...3).contains(parts[0].count), letters(parts[0]) else { return nil }
        var result = [parts[0].lowercased()]
        var index = 1
        if index < parts.count, parts[index].count == 4, letters(parts[index]) {
            result.append(parts[index].prefix(1).uppercased() + parts[index].dropFirst().lowercased())
            index += 1
        }
        if index < parts.count,
           (parts[index].count == 2 && letters(parts[index])) || (parts[index].count == 3 && digits(parts[index])) {
            result.append(parts[index].uppercased())
            index += 1
        }
        while index < parts.count {
            let part = parts[index]
            let isVariant = (5...8).contains(part.count) || (part.count == 4 && part.first?.isNumber == true)
            guard isVariant, alphanumerics(part) else { return nil }
            result.append(part.lowercased())
            index += 1
        }
        return result.joined(separator: "-")
    }

    static func isValid(_ code: String) -> Bool { canonical(code) == code }

    /// The address segment of a non-default language: the lowercased code,
    /// e.g. `pt-br` for `/pt-br/about`.
    static func routeSegment(_ code: String) -> String { code.lowercased() }
}

/// OD-038 / SF-1007-001: one language of the authored site. Optional values
/// keep "defaulted" apart from "authored": an omitted direction is the one the
/// code implies, an omitted fallback is the default language.
struct SiteLocale: Codable, Equatable, Identifiable, Sendable {
    let id: SiteLocaleID
    /// A canonical BCP 47 language tag, e.g. `en`, `fr-CA`, `zh-Hant`.
    var code: String
    /// The name authors see in SiteForge, e.g. `Français (Canada)`.
    var name: String
    /// `nil`: the direction `code` implies. A value is an authored override.
    var direction: SiteTextDirection?
    /// `nil`: the default language. A value is an authored fallback.
    var fallbackLocaleID: SiteLocaleID?

    init(id: SiteLocaleID = SiteLocaleID(), code: String, name: String,
         direction: SiteTextDirection? = nil, fallbackLocaleID: SiteLocaleID? = nil) {
        self.id = id
        self.code = code
        self.name = name
        self.direction = direction
        self.fallbackLocaleID = fallbackLocaleID
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, code, name, direction, fallbackLocaleID }

    init(from decoder: Decoder) throws {
        let actual = Set(try decoder.container(keyedBy: AnySiteForgeCodingKey.self).allKeys.map(\.stringValue))
        let required: Set<String> = [CodingKeys.id.stringValue, CodingKeys.code.stringValue, CodingKeys.name.stringValue]
        guard required.isSubset(of: actual), actual.isSubset(of: Set(CodingKeys.allCases.map(\.stringValue))) else {
            throw ModelValidationError.invalidLocalization
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        for key in [CodingKeys.direction, CodingKeys.fallbackLocaleID] where values.contains(key) {
            // Omit a defaulted value instead of storing null.
            if try values.decodeNil(forKey: key) { throw ModelValidationError.invalidLocalization }
        }
        id = try values.decode(SiteLocaleID.self, forKey: .id)
        code = try values.decode(String.self, forKey: .code)
        name = try values.decode(String.self, forKey: .name)
        direction = try values.decodeIfPresent(SiteTextDirection.self, forKey: .direction)
        fallbackLocaleID = try values.decodeIfPresent(SiteLocaleID.self, forKey: .fallbackLocaleID)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(code, forKey: .code)
        try values.encode(name, forKey: .name)
        try values.encodeIfPresent(direction, forKey: .direction)
        try values.encodeIfPresent(fallbackLocaleID, forKey: .fallbackLocaleID)
    }
}

/// OD-038 / SF-1007-001: the site's languages. The document stores no record
/// at all while the site has one unnamed language.
struct SiteLocalization: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let maximumLocales = 50
    /// Site languages are stored from document schema 27 (unreleased).
    static let documentSchema = 27

    let version: Int
    var defaultLocaleID: SiteLocaleID
    /// Ordered as authors arranged them; the default is one of them.
    var locales: [SiteLocale]

    init(defaultLocaleID: SiteLocaleID, locales: [SiteLocale]) {
        version = Self.currentVersion
        self.defaultLocaleID = defaultLocaleID
        self.locales = locales
    }

    var defaultLocale: SiteLocale? { locale(defaultLocaleID) }

    func locale(_ id: SiteLocaleID) -> SiteLocale? { locales.first { $0.id == id } }

    func locale(code: String) -> SiteLocale? {
        let wanted = code.lowercased()
        return locales.first { $0.code.lowercased() == wanted }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case version, defaultLocaleID, locales }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else { throw ModelValidationError.invalidLocalization }
        defaultLocaleID = try values.decode(SiteLocaleID.self, forKey: .defaultLocaleID)
        locales = try values.decode([SiteLocale].self, forKey: .locales)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encode(defaultLocaleID, forKey: .defaultLocaleID)
        try values.encode(locales, forKey: .locales)
    }
}

/// SF-1007-004: one reason the site languages cannot be committed, located by
/// stable identity. Messages name rules, never language names or codes.
struct SiteLocalizationIssue: Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case unsupportedVersion, noLocales, tooManyLocales, missingDefault, duplicateIdentity
        case code, duplicateCode, name, duplicateName
        case defaultHasFallback, unknownFallback, fallbackToSelf, fallbackCycle, routeCollision
    }

    let kind: Kind
    var localeID: SiteLocaleID?
    var pageID: PageID?

    init(kind: Kind, localeID: SiteLocaleID? = nil, pageID: PageID? = nil) {
        self.kind = kind
        self.localeID = localeID
        self.pageID = pageID
    }

    var message: String {
        switch kind {
        case .unsupportedVersion: "These site languages were saved by a newer SiteForge."
        case .noLocales: "A localized site needs at least one language."
        case .tooManyLocales: "A site can have at most \(SiteLocalization.maximumLocales) languages."
        case .missingDefault: "The default language must be one of the site's languages."
        case .duplicateIdentity: "Two languages share an identity."
        case .code: "A language code must be a language tag such as en, fr-CA or zh-Hant (letters, digits and hyphens, at most \(SiteLocaleCode.maximumBytes))."
        case .duplicateCode: "Another language already uses this code."
        case .name: "A language needs a name of at most 128 bytes without leading or trailing spaces."
        case .duplicateName: "Another language already has this name."
        case .defaultHasFallback: "The default language is the last fallback; it cannot fall back to another language."
        case .unknownFallback: "A language falls back to a language that no longer exists. Choose another fallback or use the default."
        case .fallbackToSelf: "A language cannot fall back to itself."
        case .fallbackCycle: "Fallbacks form a loop. Every chain of fallbacks must end at the default language."
        case .routeCollision: "A page address starts with this language's address segment. Rename the page address or choose another code."
        }
    }
}

/// SF-1007-001/003/004: the document-level language rules.
enum CanonicalLocalization {
    static let requirementIDs: Set<String> = [
        "SF-1007-001", "SF-1007-003", "SF-1007-004", "SF-1007-005", "SF-1007-008", "SF-1506-001", "SF-1506-003",
    ]

    static func issues(_ localization: SiteLocalization, pages: [DocumentPage]) -> [SiteLocalizationIssue] {
        var result: [SiteLocalizationIssue] = []
        func add(_ kind: SiteLocalizationIssue.Kind, _ locale: SiteLocaleID? = nil, page: PageID? = nil) {
            result.append(SiteLocalizationIssue(kind: kind, localeID: locale, pageID: page))
        }
        if localization.version != SiteLocalization.currentVersion { add(.unsupportedVersion) }
        if localization.locales.isEmpty { add(.noLocales) }
        if localization.locales.count > SiteLocalization.maximumLocales { add(.tooManyLocales) }
        if localization.defaultLocale == nil { add(.missingDefault, localization.defaultLocaleID) }
        let known = Set(localization.locales.map(\.id))
        var ids = Set<SiteLocaleID>(), codes = Set<String>(), names = Set<String>()
        for locale in localization.locales {
            if !ids.insert(locale.id).inserted { add(.duplicateIdentity, locale.id) }
            if !SiteLocaleCode.isValid(locale.code) {
                add(.code, locale.id)
            } else if !codes.insert(locale.code.lowercased()).inserted {
                add(.duplicateCode, locale.id)
            }
            if !WebsiteMetadata.validText(locale.name, maximumBytes: 128) {
                add(.name, locale.id)
            } else if !names.insert(locale.name.lowercased()).inserted {
                add(.duplicateName, locale.id)
            }
            guard let fallback = locale.fallbackLocaleID else { continue }
            if locale.id == localization.defaultLocaleID {
                add(.defaultHasFallback, locale.id)
            } else if fallback == locale.id {
                add(.fallbackToSelf, locale.id)
            } else if !known.contains(fallback) {
                add(.unknownFallback, locale.id)
            } else if walk(from: locale.id, in: localization).cyclic {
                add(.fallbackCycle, locale.id)
            }
        }
        // Critical invariant: a language's addresses can never collide with an
        // authored page address.
        let websitePages = pages.filter { $0.role != .componentDefinition }
        for locale in localization.locales where locale.id != localization.defaultLocaleID && SiteLocaleCode.isValid(locale.code) {
            let prefix = "/" + SiteLocaleCode.routeSegment(locale.code)
            for page in websitePages {
                let route = page.route.rawValue.lowercased()
                if route == prefix || route.hasPrefix(prefix + "/") { add(.routeCollision, locale.id, page: page.id) }
            }
        }
        return result
    }

    /// The languages visited after `id`: authored fallbacks, then the default.
    /// An unknown fallback continues at the default. `cyclic` is true when
    /// the walk returns to a visited language before reaching the default.
    static func walk(from id: SiteLocaleID, in localization: SiteLocalization) -> (chain: [SiteLocaleID], cyclic: Bool) {
        var chain: [SiteLocaleID] = []
        var visited: Set<SiteLocaleID> = [id]
        var current = id
        while current != localization.defaultLocaleID {
            let next = localization.locale(current)?.fallbackLocaleID ?? localization.defaultLocaleID
            let target = localization.locale(next) == nil ? localization.defaultLocaleID : next
            guard visited.insert(target).inserted else { return (chain, true) }
            chain.append(target)
            current = target
        }
        return (chain, false)
    }
}

/// SF-1007-003: the computed facts of one language and which rule produced them.
struct SiteLocaleResolution: Equatable, Sendable {
    enum DirectionSource: String, Sendable { case authored, impliedByCode }
    enum FallbackSource: String, Sendable { case isDefault, authored, defaultLocale }

    let localeID: SiteLocaleID
    let isDefault: Bool
    let direction: SiteTextDirection
    let directionSource: DirectionSource
    /// Languages tried after this one, in order; empty for the default.
    let fallbackChain: [SiteLocaleID]
    let fallbackSource: FallbackSource
    /// `""` for the default language, otherwise `/` plus the route segment.
    let routePrefix: String

    /// Which rule won, in words. Contains no language name or code.
    var explanation: String {
        let directionText = direction == .rightToLeft ? "right to left" : "left to right"
        let directionRule = directionSource == .authored ? "set for this language" : "implied by the language code"
        let fallbackRule: String = switch fallbackSource {
        case .isDefault: "This is the default language, so it has no fallback."
        case .authored: "Missing text is taken from \(fallbackChain.count) fallback language(s) chosen for it, ending at the default."
        case .defaultLocale: "Missing text is taken from the default language."
        }
        return "Text runs \(directionText) (\(directionRule)). \(fallbackRule)"
    }
}

enum SiteLocaleResolver {
    static func resolve(_ id: SiteLocaleID, in localization: SiteLocalization) -> SiteLocaleResolution? {
        guard let locale = localization.locale(id) else { return nil }
        let isDefault = id == localization.defaultLocaleID
        let fallbackSource: SiteLocaleResolution.FallbackSource =
            isDefault ? .isDefault : (locale.fallbackLocaleID == nil ? .defaultLocale : .authored)
        return SiteLocaleResolution(
            localeID: id, isDefault: isDefault,
            direction: locale.direction ?? SiteTextDirection.implied(byCode: locale.code),
            directionSource: locale.direction == nil ? .impliedByCode : .authored,
            fallbackChain: isDefault ? [] : CanonicalLocalization.walk(from: id, in: localization).chain,
            fallbackSource: fallbackSource,
            routePrefix: isDefault ? "" : "/" + SiteLocaleCode.routeSegment(locale.code))
    }

    /// The address of `route` in one language: unchanged for the default,
    /// `/fr` for the home page and `/fr/about` for `/about` otherwise.
    static func route(_ route: PageRoute, for id: SiteLocaleID, in localization: SiteLocalization) -> PageRoute? {
        guard let resolution = resolve(id, in: localization) else { return nil }
        guard !resolution.routePrefix.isEmpty else { return route }
        return PageRoute(rawValue: route.rawValue == "/" ? resolution.routePrefix : resolution.routePrefix + route.rawValue)
    }

    /// SF-1007-003: the first language in `id`'s chain (itself first) that
    /// `has` accepts, e.g. the first one with a translation; `nil` when none.
    static func firstAvailable(_ id: SiteLocaleID, in localization: SiteLocalization,
                               where has: (SiteLocaleID) -> Bool) -> SiteLocaleID? {
        guard localization.locale(id) != nil else { return nil }
        let rest = id == localization.defaultLocaleID ? [] : CanonicalLocalization.walk(from: id, in: localization).chain
        return ([id] + rest).first(where: has)
    }
}

enum SiteLocalizationEditError: Error, Equatable, LocalizedError {
    case busy, stale, revisionExhausted, unchanged
    case invalidCode, duplicateCode, unknownLocale, cannotRemoveDefault
    case invalid([SiteLocalizationIssue])
    case refused(String)

    var category: String {
        switch self {
        case .busy: "busy"
        case .stale: "stale"
        case .revisionExhausted: "revision-exhausted"
        case .unchanged: "unchanged"
        case .invalidCode: "invalid-code"
        case .duplicateCode: "duplicate-code"
        case .unknownLocale: "unknown-locale"
        case .cannotRemoveDefault: "default-locale"
        case .invalid: "invalid"
        case .refused: "refused"
        }
    }

    var errorDescription: String? {
        switch self {
        case .busy: "Languages can't be changed while the project is busy. Nothing changed."
        case .stale: "The project changed after Languages opened. Nothing changed; cancel and open Languages again."
        case .revisionExhausted: "The document revision cannot accept another transaction. Nothing changed."
        case .unchanged: "Languages are unchanged."
        case .invalidCode: "SF-1007-004: Enter a language tag such as en, fr-CA or zh-Hant."
        case .duplicateCode: "SF-1007-004: The site already has this language."
        case .unknownLocale: "This language is no longer part of the site."
        case .cannotRemoveDefault: "The default language can't be removed. Make another language the default first."
        case .invalid(let issues): issues.first.map { "SF-1007-004: \($0.message)" } ?? "Languages are invalid."
        case .refused(let reason): reason
        }
    }
}

/// SF-1007-002: pure draft operations for the Languages editor, automation
/// and tests. Only `prepare` produces a command.
enum SiteLocalizationEditing {
    static func prepare(_ localization: SiteLocalization?, openingRevision: UInt64, document: CanonicalDocument,
                        isLifecycleAvailable: Bool) throws -> DocumentCommand {
        guard isLifecycleAvailable else { throw SiteLocalizationEditError.busy }
        guard openingRevision == document.revision else { throw SiteLocalizationEditError.stale }
        guard document.revision < UInt64.max - 1 else { throw SiteLocalizationEditError.revisionExhausted }
        if let localization {
            let issues = CanonicalLocalization.issues(localization, pages: document.pages)
            guard issues.isEmpty else { throw SiteLocalizationEditError.invalid(issues) }
        }
        guard localization != document.localization else { throw SiteLocalizationEditError.unchanged }
        let command = DocumentCommand.setLocalization(SetLocalizationCommand(documentID: document.id, localization: localization))
        // OD-038 part 2 (ADR-0081): translations follow the change in the same
        // undoable edit (gone languages lose theirs; a new default swaps values).
        let translationCommands = SiteTranslationEditing.transitionCommands(from: document.localization, to: localization,
                                                                            in: document)
        guard translationCommands.isEmpty else {
            let grouped = DocumentCommand.batch(translationCommands + [command])
            let availability = CommandRegistry().availability(for: grouped, in: document)
            guard availability.isEnabled else {
                throw SiteLocalizationEditError.refused(availability.disabledReason ?? "The languages could not be changed. Nothing changed.")
            }
            return grouped
        }
        var candidate = document
        candidate.localization = localization
        do {
            try candidate.validate()
        } catch {
            throw SiteLocalizationEditError.refused(error.localizedDescription)
        }
        return command
    }

    /// Localization with one default language (the site's current language).
    static func start(code: String = "en", name: String? = nil) throws -> SiteLocalization {
        guard let canonical = SiteLocaleCode.canonical(code) else { throw SiteLocalizationEditError.invalidCode }
        let empty = SiteLocalization(defaultLocaleID: SiteLocaleID(), locales: [])
        let locale = SiteLocale(code: canonical, name: name ?? suggestedName(for: canonical, in: empty))
        return SiteLocalization(defaultLocaleID: locale.id, locales: [locale])
    }

    /// Appends a language that falls back to the default.
    @discardableResult
    static func addLocale(code: String, name: String? = nil, to localization: inout SiteLocalization) throws -> SiteLocale {
        guard let canonical = SiteLocaleCode.canonical(code) else { throw SiteLocalizationEditError.invalidCode }
        guard localization.locale(code: canonical) == nil else { throw SiteLocalizationEditError.duplicateCode }
        let locale = SiteLocale(code: canonical, name: name ?? suggestedName(for: canonical, in: localization))
        localization.locales.append(locale)
        return locale
    }

    /// Removing a language restores the next valid source: languages that
    /// fell back to it fall back to the default again.
    static func removeLocale(_ id: SiteLocaleID, from localization: inout SiteLocalization) throws {
        guard localization.locale(id) != nil else { throw SiteLocalizationEditError.unknownLocale }
        guard id != localization.defaultLocaleID else { throw SiteLocalizationEditError.cannotRemoveDefault }
        localization.locales.removeAll { $0.id == id }
        for index in localization.locales.indices where localization.locales[index].fallbackLocaleID == id {
            localization.locales[index].fallbackLocaleID = nil
        }
    }

    /// The new default keeps no fallback; the old default then falls back to it.
    static func makeDefault(_ id: SiteLocaleID, in localization: inout SiteLocalization) throws {
        guard let index = localization.locales.firstIndex(where: { $0.id == id }) else {
            throw SiteLocalizationEditError.unknownLocale
        }
        localization.defaultLocaleID = id
        localization.locales[index].fallbackLocaleID = nil
    }

    /// A readable, unique name for a new language, e.g. "French (Canada)".
    static func suggestedName(for code: String, in localization: SiteLocalization) -> String {
        let described = Locale(identifier: "en_US_POSIX").localizedString(forIdentifier: code) ?? code
        let base = WebsiteMetadata.validText(described, maximumBytes: 96) ? described : code
        let names = Set(localization.locales.map { $0.name.lowercased() })
        return names.contains(base.lowercased()) ? "\(base) (\(code))" : base
    }
}

/// SF-1007-008: sanitized record of one language edit. Holds identities and
/// counts, never language names or codes.
struct SiteLocalizationEditDiagnostic: Equatable, Sendable {
    let requirementID: String
    let operation: String
    let localeIdentifiers: [String]
    let localeCount: Int
    let durationMilliseconds: Int
    let failureCategory: String

    init(requirementID: String = "SF-1007-002", operation: String, localization: SiteLocalization?,
         durationMilliseconds: Int, error: Error?) {
        self.requirementID = requirementID
        self.operation = operation
        localeIdentifiers = localization?.locales.map(\.id.description) ?? []
        localeCount = localization?.locales.count ?? 0
        self.durationMilliseconds = durationMilliseconds
        if let error {
            failureCategory = (error as? SiteLocalizationEditError)?.category ?? "unexpected"
        } else {
            failureCategory = "none"
        }
    }
}

// MARK: - SF-1007 / SF-1506 per-node translations (OD-038 part 2, ADR-0081)

/// OD-038 / SF-1007-001: a translatable value of a node. The node's own
/// property is the default language's value; every other language stores an
/// authored string property `locale.translation.v1.<language id>.<field>` on
/// the same node, so renaming or recoding a language never rewrites it.
enum SiteTranslationField: String, CaseIterable, Sendable {
    case text
    case imageAssetID = "image.assetID"
    case imageAlt = "image.alt"

    var title: String {
        switch self {
        case .text: "Text"
        case .imageAssetID: "Image"
        case .imageAlt: "Alternative text"
        }
    }

    /// The property that holds the default language's value on a node of
    /// `kind`, or `nil` when this field does not apply to that kind.
    func baseKey(for kind: NodeKind) -> String? {
        switch self {
        case .text:
            if kind == .text { return "content.text" }
            return kind.isLinkControl ? CanonicalLinkTarget.labelKey : nil
        case .imageAssetID:
            return kind == .image ? CanonicalImageStyle.namespace + "assetID" : nil
        case .imageAlt:
            return kind == .image ? CanonicalImageStyle.namespace + "alt" : nil
        }
    }

    static func fields(for kind: NodeKind) -> [SiteTranslationField] {
        allCases.filter { $0.baseKey(for: kind) != nil }
    }
}

/// The stable property key of one translation (language identity + field).
struct SiteTranslationKey: Hashable, Sendable {
    static let namespace = "locale.translation.v1."
    let localeID: SiteLocaleID
    let field: SiteTranslationField

    init(localeID: SiteLocaleID, field: SiteTranslationField) {
        self.localeID = localeID
        self.field = field
    }

    /// `nil` for a key outside the namespace and for a malformed one (the
    /// language identity must be written in its canonical lowercase form).
    init?(rawValue: String) {
        guard rawValue.hasPrefix(Self.namespace) else { return nil }
        let rest = String(rawValue.dropFirst(Self.namespace.count))
        guard let dot = rest.firstIndex(of: ".") else { return nil }
        let rawID = String(rest[..<dot])
        guard let id = SiteLocaleID(uuidString: rawID), id.description == rawID,
              let field = SiteTranslationField(rawValue: String(rest[rest.index(after: dot)...])) else { return nil }
        self.init(localeID: id, field: field)
    }

    var rawValue: String { Self.namespace + localeID.description + "." + field.rawValue }
}

/// SF-1007-001/004: the translation rules and read access.
enum CanonicalTranslations {
    static let requirementIDs: Set<String> = [
        "SF-1007-001", "SF-1007-002", "SF-1007-003", "SF-1007-004", "SF-1007-005", "SF-1007-008", "SF-1506-001",
    ]
    static let maximumTextBytes = 64 * 1_024
    static let maximumAltBytes = 4_096
    /// Every language of a full site, each with every field.
    static var maximumPerNode: Int { SiteLocalization.maximumLocales * SiteTranslationField.allCases.count }

    /// Node rules: every key in the namespace parses and applies to the
    /// node's kind; values are authored strings within limits; translated
    /// images reference an existing asset.
    static func validate(_ node: DocumentNode, assetIDs: Set<AssetID>) throws {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix(SiteTranslationKey.namespace) }
        guard owned.count <= maximumPerNode else { throw ModelValidationError.invalidTranslation }
        for property in owned {
            guard let key = SiteTranslationKey(rawValue: property.key.rawValue),
                  key.field.baseKey(for: node.kind) != nil,
                  property.origin == .authored,
                  case .string(let value) = property.value,
                  isValid(value, for: key.field, assetIDs: assetIDs) else {
                throw ModelValidationError.invalidTranslation
            }
        }
    }

    /// Document rule: the default language has no translation (its value is
    /// the node's own). Translations of languages the site no longer has stay
    /// representable as orphans: reported, never shown, dropped by the next
    /// language edit.
    static func validate(_ document: CanonicalDocument) throws {
        guard let defaultID = document.localization?.defaultLocaleID else { return }
        for page in document.pages {
            for node in page.nodes where translations(on: node).contains(where: { $0.key.localeID == defaultID }) {
                throw ModelValidationError.invalidTranslation
            }
        }
    }

    static func isValid(_ value: String, for field: SiteTranslationField, assetIDs: Set<AssetID>) -> Bool {
        switch field {
        case .text:
            return value.utf8.count <= maximumTextBytes && !hasControlCharacters(value)
        case .imageAlt:
            return value.utf8.count <= maximumAltBytes && !hasControlCharacters(value)
        case .imageAssetID:
            guard let id = AssetID(uuidString: value) else { return false }
            return assetIDs.contains(id)
        }
    }

    private static func hasControlCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t" }
    }

    /// The translations stored on `node`, in property order.
    static func translations(on node: DocumentNode) -> [(key: SiteTranslationKey, property: NodeProperty)] {
        node.properties.compactMap { property in
            SiteTranslationKey(rawValue: property.key.rawValue).map { (key: $0, property: property) }
        }
    }

    static func value(_ field: SiteTranslationField, for localeID: SiteLocaleID, on node: DocumentNode) -> String? {
        node.insertionStringProperty(SiteTranslationKey(localeID: localeID, field: field).rawValue)
    }

    /// The default language's value: the node's own property.
    static func baseValue(_ field: SiteTranslationField, on node: DocumentNode) -> String? {
        guard let key = field.baseKey(for: node.kind) else { return nil }
        return node.insertionStringProperty(key)
    }

    /// SF-0807: a translated image keeps its asset in use.
    static func usesAsset(_ id: AssetID, in document: CanonicalDocument) -> Bool {
        document.pages.contains { page in
            page.nodes.contains { node in
                translations(on: node).contains { entry in
                    guard entry.key.field == .imageAssetID, case .string(let raw) = entry.property.value else { return false }
                    return AssetID(uuidString: raw) == id
                }
            }
        }
    }
}

/// SF-1007-003: one translatable value in one language and which rule chose it.
struct SiteTranslationResolution: Equatable, Sendable {
    enum Source: String, Sendable { case translation, fallback, defaultValue, missing }

    let field: SiteTranslationField
    let localeID: SiteLocaleID
    let value: String?
    /// The language whose value is shown; `nil` when nothing has one.
    let sourceLocaleID: SiteLocaleID?
    let source: Source

    /// Which rule won, in words. Contains no value, language name or code.
    var explanation: String {
        switch source {
        case .translation: "\(field.title) is translated for this language."
        case .fallback: "\(field.title) is not translated for this language; a fallback language's translation is shown."
        case .defaultValue:
            sourceLocaleID == localeID
                ? "\(field.title) is the default language's own value."
                : "\(field.title) is not translated for this language or its fallbacks; the default language's value is shown."
        case .missing: "\(field.title) has no value in this language, its fallbacks or the default language."
        }
    }
}

enum SiteTranslationResolver {
    /// The value of `field` on `node` in one language: its own translation,
    /// else the first fallback language with one, else the node's own value.
    /// `nil` for an unknown language or a field that does not apply.
    static func resolve(_ field: SiteTranslationField, on node: DocumentNode, for localeID: SiteLocaleID,
                        in localization: SiteLocalization) -> SiteTranslationResolution? {
        guard localization.locale(localeID) != nil, field.baseKey(for: node.kind) != nil else { return nil }
        let defaultID = localization.defaultLocaleID
        let found = SiteLocaleResolver.firstAvailable(localeID, in: localization) { candidate in
            candidate == defaultID
                ? CanonicalTranslations.baseValue(field, on: node) != nil
                : CanonicalTranslations.value(field, for: candidate, on: node) != nil
        }
        guard let found else {
            return SiteTranslationResolution(field: field, localeID: localeID, value: nil, sourceLocaleID: nil, source: .missing)
        }
        if found == defaultID {
            return SiteTranslationResolution(field: field, localeID: localeID, value: CanonicalTranslations.baseValue(field, on: node),
                                             sourceLocaleID: found, source: .defaultValue)
        }
        return SiteTranslationResolution(field: field, localeID: localeID,
                                         value: CanonicalTranslations.value(field, for: found, on: node),
                                         sourceLocaleID: found, source: found == localeID ? .translation : .fallback)
    }
}

/// SF-1007-002/004: one value not translated yet, or a translation no
/// language uses any more.
struct SiteTranslationGap: Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable { case missing, orphaned }

    let kind: Kind
    let localeID: SiteLocaleID
    let pageID: PageID
    let nodeID: NodeID
    let field: SiteTranslationField
    /// For `missing`: the language whose value is shown instead.
    let shownLocaleID: SiteLocaleID?
}

/// SF-1007-002: missing translations are visible before publish. Text and
/// the alternative text of non-decorative images need a translation;
/// translated images are optional.
struct SiteTranslationReport: Equatable, Sendable {
    let gaps: [SiteTranslationGap]
    /// Values that need a translation in every non-default language.
    let translatableCount: Int

    func missingCount(_ localeID: SiteLocaleID) -> Int {
        gaps.filter { $0.kind == .missing && $0.localeID == localeID }.count
    }

    var orphanedCount: Int { gaps.filter { $0.kind == .orphaned }.count }

    /// Plain-language summary without values, names or codes.
    var summary: String {
        let missing = gaps.filter { $0.kind == .missing }.count
        guard missing > 0 || orphanedCount > 0 else { return "Everything that needs a translation is translated." }
        var parts: [String] = []
        if missing > 0 {
            parts.append("\(missing) translation(s) missing; until they are added, a fallback language's value is shown")
        }
        if orphanedCount > 0 {
            parts.append("\(orphanedCount) translation(s) belong to languages the site no longer has and are never shown")
        }
        return parts.joined(separator: ". ") + "."
    }

    static func requiredFields(on node: DocumentNode) -> [SiteTranslationField] {
        var result: [SiteTranslationField] = []
        if let text = CanonicalTranslations.baseValue(.text, on: node),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(.text)
        }
        if node.kind == .image, !node.insertionBooleanProperty(CanonicalImageStyle.namespace + "decorative"),
           let alt = CanonicalTranslations.baseValue(.imageAlt, on: node),
           !alt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(.imageAlt)
        }
        return result
    }

    /// Deterministic: pages in document order, nodes in tree order, languages
    /// in the order authors arranged them.
    static func build(_ document: CanonicalDocument) -> SiteTranslationReport {
        let localization = document.localization
        let known = Set(localization?.locales.map(\.id) ?? [])
        let others = localization.map { record in record.locales.filter { $0.id != record.defaultLocaleID } } ?? []
        var gaps: [SiteTranslationGap] = []
        var translatable = 0
        for page in document.pages {
            for node in page.canonicalDepthFirstNodes() {
                for entry in CanonicalTranslations.translations(on: node) where !known.contains(entry.key.localeID) {
                    gaps.append(SiteTranslationGap(kind: .orphaned, localeID: entry.key.localeID, pageID: page.id,
                                                   nodeID: node.id, field: entry.key.field, shownLocaleID: nil))
                }
                guard let localization else { continue }
                for field in requiredFields(on: node) {
                    translatable += 1
                    for locale in others where CanonicalTranslations.value(field, for: locale.id, on: node) == nil {
                        let shown = SiteTranslationResolver.resolve(field, on: node, for: locale.id, in: localization)?.sourceLocaleID
                        gaps.append(SiteTranslationGap(kind: .missing, localeID: locale.id, pageID: page.id,
                                                       nodeID: node.id, field: field, shownLocaleID: shown))
                    }
                }
            }
        }
        return SiteTranslationReport(gaps: gaps, translatableCount: translatable)
    }
}

enum SiteTranslationEditError: Error, Equatable, LocalizedError {
    case busy, stale, revisionExhausted, notLocalized, unknownLocale, defaultLocale
    case unknownNode, unsupportedField, unchanged, invalidValue
    case refused(String)

    var category: String {
        switch self {
        case .busy: "busy"
        case .stale: "stale"
        case .revisionExhausted: "revision-exhausted"
        case .notLocalized: "not-localized"
        case .unknownLocale: "unknown-locale"
        case .defaultLocale: "default-locale"
        case .unknownNode: "unknown-node"
        case .unsupportedField: "unsupported-field"
        case .unchanged: "unchanged"
        case .invalidValue: "invalid-value"
        case .refused: "refused"
        }
    }

    var errorDescription: String? {
        switch self {
        case .busy: "Translations can't be changed while the project is busy. Nothing changed."
        case .stale: "The project changed after the translation was opened. Nothing changed; open it again."
        case .revisionExhausted: "The document revision cannot accept another transaction. Nothing changed."
        case .notLocalized: "Add a second language in Languages before translating."
        case .unknownLocale: "This language is no longer part of the site."
        case .defaultLocale: "The default language's value is the element's own content. Edit it on the canvas or in the Inspector."
        case .unknownNode: "This element no longer exists on the page."
        case .unsupportedField: "This element has no value of that kind to translate."
        case .unchanged: "The translation is unchanged."
        case .invalidValue: "SF-1007-004: Translated text must be at most 64 KB without control characters, alternative text at most 4 KB, and a translated image must be in the project's assets."
        case .refused(let reason): reason
        }
    }
}

/// SF-1007-002: translation edits for the editor, automation and tests. Each
/// edit is one undoable grouped edit, validated before it is returned.
enum SiteTranslationEditing {
    /// Sets (`value`) or clears (`nil`) one translation.
    static func prepare(_ value: String?, field: SiteTranslationField, nodeID: NodeID, pageID: PageID,
                        localeID: SiteLocaleID, openingRevision: UInt64, document: CanonicalDocument,
                        isLifecycleAvailable: Bool) throws -> DocumentCommand {
        guard isLifecycleAvailable else { throw SiteTranslationEditError.busy }
        guard openingRevision == document.revision else { throw SiteTranslationEditError.stale }
        guard document.revision < UInt64.max - 1 else { throw SiteTranslationEditError.revisionExhausted }
        guard let localization = document.localization else { throw SiteTranslationEditError.notLocalized }
        guard localization.locale(localeID) != nil else { throw SiteTranslationEditError.unknownLocale }
        guard localeID != localization.defaultLocaleID else { throw SiteTranslationEditError.defaultLocale }
        guard let node = document.pages.first(where: { $0.id == pageID })?.nodes.first(where: { $0.id == nodeID }) else {
            throw SiteTranslationEditError.unknownNode
        }
        guard field.baseKey(for: node.kind) != nil else { throw SiteTranslationEditError.unsupportedField }
        let key = SiteTranslationKey(localeID: localeID, field: field).rawValue
        let existing = node.insertionProperty(key)
        let command: DocumentCommand
        if let value {
            guard CanonicalTranslations.isValid(value, for: field, assetIDs: Set(document.imageAssets.map(\.id))) else {
                throw SiteTranslationEditError.invalidValue
            }
            if let existing, existing.value == .string(value) { throw SiteTranslationEditError.unchanged }
            command = .setProperty(SetPropertyCommand(pageID: pageID, nodeID: nodeID, property: NodeProperty(
                id: existing?.id ?? PropertyID(), key: PropertyKey(rawValue: key), value: .string(value), origin: .authored)))
        } else {
            guard let existing else { throw SiteTranslationEditError.unchanged }
            command = .removeProperty(RemovePropertyCommand(pageID: pageID, nodeID: nodeID, propertyID: existing.id))
        }
        // A grouped edit is validated as a whole before it is offered.
        let grouped = DocumentCommand.batch([command])
        let availability = CommandRegistry().availability(for: grouped, in: document)
        guard availability.isEnabled else {
            throw SiteTranslationEditError.refused(availability.disabledReason ?? "The translation could not be changed. Nothing changed.")
        }
        return grouped
    }

    /// ADR-0087: the properties a paste may keep. A translation keyed to the
    /// destination's default language cannot exist there (that value is the
    /// element's own). Projects made from one template share language
    /// identities, so a paste between them drops such a translation instead
    /// of being refused.
    static func pastableProperties(_ properties: [NodeProperty], into localization: SiteLocalization?) -> [NodeProperty] {
        guard let defaultID = localization?.defaultLocaleID else { return properties }
        return properties.filter { SiteTranslationKey(rawValue: $0.key.rawValue)?.localeID != defaultID }
    }

    /// `pastableProperties` for every node of an imported component definition.
    static func pastablePage(_ page: DocumentPage, into localization: SiteLocalization?) -> DocumentPage {
        var result = page
        for index in result.nodes.indices {
            result.nodes[index].properties = pastableProperties(result.nodes[index].properties, into: localization)
        }
        return result
    }

    /// How many translations changing the languages to `localization` drops:
    /// those of removed languages (and orphans), or all when languages are off.
    static func droppedTranslationCount(to localization: SiteLocalization?, in document: CanonicalDocument) -> Int {
        let kept = Set(localization?.locales.map(\.id) ?? [])
        var count = 0
        for page in document.pages {
            for node in page.nodes {
                count += CanonicalTranslations.translations(on: node).filter { !kept.contains($0.key.localeID) }.count
            }
        }
        return count
    }

    /// The property edits that keep translations consistent with a language
    /// change, applied in the same grouped edit as `setLocalization`:
    /// translations of languages that are gone are removed; when the default
    /// moves to another existing language, that language's translation
    /// becomes the node's own value and the old default's value becomes its
    /// translation (no text is lost; Undo restores both). When the old
    /// default is removed in the same edit, its values go with it: the new
    /// default's translations still become the nodes' own values, because a
    /// translation can never stay keyed to the default language.
    static func transitionCommands(from old: SiteLocalization?, to new: SiteLocalization?,
                                   in document: CanonicalDocument) -> [DocumentCommand] {
        let kept = Set(new?.locales.map(\.id) ?? [])
        var swap: (from: SiteLocaleID, to: SiteLocaleID, keepsOldDefault: Bool)?
        if let old, let new, old.defaultLocaleID != new.defaultLocaleID, old.locale(new.defaultLocaleID) != nil {
            swap = (from: old.defaultLocaleID, to: new.defaultLocaleID,
                    keepsOldDefault: new.locale(old.defaultLocaleID) != nil)
        }
        var commands: [DocumentCommand] = []
        for page in document.pages {
            for node in page.nodes {
                for entry in CanonicalTranslations.translations(on: node) where !kept.contains(entry.key.localeID) {
                    commands.append(.removeProperty(RemovePropertyCommand(pageID: page.id, nodeID: node.id,
                                                                          propertyID: entry.property.id)))
                }
                guard let swap else { continue }
                for field in SiteTranslationField.fields(for: node.kind) {
                    let promotedKey = SiteTranslationKey(localeID: swap.to, field: field).rawValue
                    guard let promoted = node.insertionProperty(promotedKey) else { continue }
                    guard let baseKey = field.baseKey(for: node.kind), let base = node.insertionProperty(baseKey),
                          case .string(let promotedValue) = promoted.value, case .string = base.value else {
                        // Nothing to swap with: the translation cannot stay keyed to the default.
                        commands.append(.removeProperty(RemovePropertyCommand(pageID: page.id, nodeID: node.id,
                                                                              propertyID: promoted.id)))
                        continue
                    }
                    commands.append(.setProperty(SetPropertyCommand(pageID: page.id, nodeID: node.id, property: NodeProperty(
                        id: base.id, key: base.key, value: .string(promotedValue), origin: .authored))))
                    guard swap.keepsOldDefault else {
                        commands.append(.removeProperty(RemovePropertyCommand(pageID: page.id, nodeID: node.id,
                                                                              propertyID: promoted.id)))
                        continue
                    }
                    commands.append(.setProperty(SetPropertyCommand(pageID: page.id, nodeID: node.id, property: NodeProperty(
                        id: promoted.id, key: PropertyKey(rawValue: SiteTranslationKey(localeID: swap.from, field: field).rawValue),
                        value: base.value, origin: .authored))))
                }
            }
        }
        return commands
    }
}

/// SF-1007-008: sanitized record of one translation edit. Holds identities,
/// never values, language names or codes.
struct SiteTranslationEditDiagnostic: Equatable, Sendable {
    let requirementID: String
    let operation: String
    let nodeIdentifier: String
    let localeIdentifier: String
    let field: String
    let durationMilliseconds: Int
    let failureCategory: String

    init(requirementID: String = "SF-1007-002", operation: String, nodeID: NodeID, localeID: SiteLocaleID,
         field: SiteTranslationField, durationMilliseconds: Int, error: Error?) {
        self.requirementID = requirementID
        self.operation = operation
        nodeIdentifier = nodeID.description
        localeIdentifier = localeID.description
        self.field = field.rawValue
        self.durationMilliseconds = durationMilliseconds
        if let error {
            failureCategory = (error as? SiteTranslationEditError)?.category ?? "unexpected"
        } else {
            failureCategory = "none"
        }
    }
}

// MARK: - SF-1007 Inspector translations (OD-038 part 4b, ADR-0084)

/// OD-038 part 4b: the one element the Inspector's Translations section shows.
struct SiteTranslationInspectorTarget: Equatable, Sendable {
    let pageID: PageID
    let node: DocumentNode
}

/// One translatable value of an element in one language, as the Inspector shows it.
struct SiteTranslationInspectorRow: Equatable, Sendable {
    let field: SiteTranslationField
    /// The value the language shows now and which rule chose it.
    let resolution: SiteTranslationResolution
    /// The language's own translation; `nil` when it has none.
    let translation: String?
    /// Text and the alternative text of a non-decorative image need a
    /// translation (`SiteTranslationReport.requiredFields`); images do not.
    let needsTranslation: Bool

    var isMissing: Bool { needsTranslation && translation == nil }
}

/// SF-1007-002/003/006: the read side of the Inspector's Translations
/// section. Pure, and reads only the one element, so it stays cheap on large
/// sites. Edits go through `SiteTranslationEditing.prepare`.
enum SiteTranslationInspection {
    /// One element selected on a website page or in an open component
    /// definition, of a kind with translatable values, while the site has a
    /// language besides the default. Definition translations are exported for
    /// every instance and counted by `SiteTranslationReport`, so they must be
    /// editable too (ADR-0087).
    static func target(selectedNodeIDs: [NodeID], pageID: PageID?,
                       in document: CanonicalDocument) -> SiteTranslationInspectorTarget? {
        guard selectedNodeIDs.count == 1, let nodeID = selectedNodeIDs.first, let pageID,
              !translatableLocales(document.localization).isEmpty,
              let page = document.pages.first(where: { $0.id == pageID }),
              let node = page.nodes.first(where: { $0.id == nodeID }),
              !SiteTranslationField.fields(for: node.kind).isEmpty else { return nil }
        return SiteTranslationInspectorTarget(pageID: pageID, node: node)
    }

    /// Every language except the default, in the order authors arranged them.
    static func translatableLocales(_ localization: SiteLocalization?) -> [SiteLocale] {
        guard let localization else { return [] }
        return localization.locales.filter { $0.id != localization.defaultLocaleID }
    }

    /// The language the section shows: `preferred` while it can be
    /// translated, otherwise the first language that can.
    static func locale(preferred: SiteLocaleID?, in localization: SiteLocalization?) -> SiteLocaleID? {
        let locales = translatableLocales(localization)
        if let preferred, locales.contains(where: { $0.id == preferred }) { return preferred }
        return locales.first?.id
    }

    /// SF-1506: right-to-left languages are typed right to left.
    static func isRightToLeft(_ localeID: SiteLocaleID, in localization: SiteLocalization) -> Bool {
        SiteLocaleResolver.resolve(localeID, in: localization)?.direction == .rightToLeft
    }

    /// The element's translatable values in one language, in field order.
    static func rows(for node: DocumentNode, localeID: SiteLocaleID,
                     in localization: SiteLocalization) -> [SiteTranslationInspectorRow] {
        let required = Set(SiteTranslationReport.requiredFields(on: node))
        return SiteTranslationField.fields(for: node.kind).compactMap { field in
            SiteTranslationResolver.resolve(field, on: node, for: localeID, in: localization).map { resolution in
                SiteTranslationInspectorRow(field: field, resolution: resolution,
                                            translation: CanonicalTranslations.value(field, for: localeID, on: node),
                                            needsTranslation: required.contains(field))
            }
        }
    }

    /// SF-1007-002: the element's missing translations in every language;
    /// the same gaps, in the same order, as `SiteTranslationReport.build`
    /// lists for it.
    static func missingTranslations(on node: DocumentNode, pageID: PageID,
                                    in localization: SiteLocalization) -> [SiteTranslationGap] {
        let others = translatableLocales(localization)
        var gaps: [SiteTranslationGap] = []
        for field in SiteTranslationReport.requiredFields(on: node) {
            for locale in others where CanonicalTranslations.value(field, for: locale.id, on: node) == nil {
                let shown = SiteTranslationResolver.resolve(field, on: node, for: locale.id, in: localization)?.sourceLocaleID
                gaps.append(SiteTranslationGap(kind: .missing, localeID: locale.id, pageID: pageID, nodeID: node.id,
                                               field: field, shownLocaleID: shown))
            }
        }
        return gaps
    }

    /// Plain-language summary for the Inspector. Names languages, so it is
    /// shown to the author only, never written to diagnostics.
    static func missingSummary(_ gaps: [SiteTranslationGap], in localization: SiteLocalization) -> String {
        guard !gaps.isEmpty else { return "This element is translated in every language." }
        var names: [String] = []
        for gap in gaps {
            if let name = localization.locale(gap.localeID)?.name, !names.contains(name) { names.append(name) }
        }
        return "\(gaps.count) translation(s) missing for this element (\(names.joined(separator: ", "))). "
            + "Until they are added, a fallback language's value is shown."
    }
}

// MARK: - SF-1007 / SF-1506 language shown on the canvas (OD-038 part 4c, ADR-0085)

/// One language the canvas and Local Preview can show.
struct SiteCanvasLanguageOption: Equatable, Sendable {
    let id: SiteLocaleID
    let name: String
    let isDefault: Bool
    let isRightToLeft: Bool
}

/// OD-038 / SF-1007-003, SF-1506-003: which language the canvas and Local
/// Preview show. View state only: never saved, never part of the document and
/// never an undoable edit. A language shows exactly what export writes for it
/// (`SiteLanguageOutput.translatedDocument`).
enum SiteCanvasLanguage {
    static let requirementIDs: Set<String> = ["SF-1007-002", "SF-1007-003", "SF-1007-008", "SF-1506-003"]

    static let textEditingRefusal = "Text editing on the canvas is off while another language is shown. "
        + "Translate in the Inspector's Translations section, or show the default language to edit the text itself."

    /// The default language first, then the others in the order authors arranged them.
    static func options(_ localization: SiteLocalization?) -> [SiteCanvasLanguageOption] {
        guard let localization else { return [] }
        let ordered = localization.locales.filter { $0.id == localization.defaultLocaleID }
            + localization.locales.filter { $0.id != localization.defaultLocaleID }
        return ordered.map { locale in
            SiteCanvasLanguageOption(id: locale.id, name: locale.name, isDefault: locale.id == localization.defaultLocaleID,
                                     isRightToLeft: SiteTranslationInspection.isRightToLeft(locale.id, in: localization))
        }
    }

    /// The language shown instead of the document itself, or `nil` for a site
    /// without languages, the default language and a language the site no
    /// longer has (the canvas then shows the default again).
    static func shownLocale(_ preferred: SiteLocaleID?, in localization: SiteLocalization?) -> SiteLocaleID? {
        guard let preferred, let localization, preferred != localization.defaultLocaleID,
              localization.locale(preferred) != nil else { return nil }
        return preferred
    }

    /// The document as the canvas shows it; `document` itself for the default.
    static func displayedDocument(_ document: CanonicalDocument, showing preferred: SiteLocaleID?,
                                  in localization: SiteLocalization?) -> CanonicalDocument {
        guard let localization, let id = shownLocale(preferred, in: localization) else { return document }
        return SiteLanguageOutput.translatedDocument(document, to: id, in: localization)
    }

    /// What the canvas shows, for the author; empty while the default is
    /// shown. Names the language, so it is never written to diagnostics.
    static func status(showing preferred: SiteLocaleID?, in document: CanonicalDocument) -> String {
        guard let localization = document.localization, let id = shownLocale(preferred, in: localization),
              let locale = localization.locale(id) else { return "" }
        let missing = SiteTranslationReport.build(document).missingCount(id)
        var parts = ["Showing \(locale.name)."]
        parts.append(missing == 0
            ? "Everything that needs a translation is translated."
            : "\(missing) value(s) are not translated yet and show a fallback language's value.")
        if SiteTranslationInspection.isRightToLeft(id, in: localization) {
            parts.append(SiteRightToLeftCanvasLayout.statusNote)
        }
        parts.append(textEditingRefusal)
        return parts.joined(separator: " ")
    }
}

/// SF-1007-008: sanitized record of one canvas language change. Holds the
/// language identity only, never a language name, code or value.
struct SiteCanvasLanguageDiagnostic: Equatable, Sendable {
    let requirementID: String
    let operation: String
    let localeIdentifier: String?
    let durationMilliseconds: Int
    let failureCategory: String
}

// MARK: - SF-1007 / SF-1506 right-to-left canvas layout (OD-038 part 4c, ADR-0086)

/// OD-038 part 4c (ADR-0086): the canvas layout of a right-to-left language.
/// Mirrors what `dir="rtl"` changes in export: children that a Stack,
/// Section, Form, Grid or padded Frame lays out (flex and grid output) and
/// page navigation links run from the right edge of their parent; children
/// placed absolutely (export's `left:`) keep their offset from the parent's
/// left edge and move with it. Vertical positions and sizes never change.
/// View only: the document and the frames transforms change are untouched.
enum SiteRightToLeftCanvasLayout {
    static let requirementIDs: Set<String> = ["SF-1007-002", "SF-1007-003", "SF-1506-003"]

    static let statusNote = "It reads right to left, so the canvas mirrors the layout the way exported pages do. "
        + "Moving and resizing on the canvas are off while it is shown."

    static let transformRefusal = "Moving and resizing on the canvas are off while a right-to-left language is shown, "
        + "because the canvas shows the mirrored layout. Show the default language to change the layout."

    /// ADR-0087: the status while the author mirrors a right-to-left default language.
    static let defaultMirrorStatusNote = "The default language reads right to left, so the canvas mirrors the layout "
        + "the way exported pages do. Moving, resizing and text editing on the canvas are off until Mirror Layout is turned off."

    /// ADR-0087: transforms and canvas text editing are refused while the default is mirrored.
    static let defaultMirrorRefusal = "Moving, resizing and text editing on the canvas are off while Mirror Layout is on, "
        + "because the canvas shows the mirrored layout. Turn off Mirror Layout to change the layout or edit text on the canvas."

    /// ADR-0087: the default language itself reads right to left. Export then
    /// writes `dir="rtl"` at the site root; the canvas mirrors it only while
    /// the author turns on Mirror Layout, because transforms need the authored frames.
    static func defaultReadsRightToLeft(_ localization: SiteLocalization?) -> Bool {
        guard let localization else { return false }
        return SiteTranslationInspection.isRightToLeft(localization.defaultLocaleID, in: localization)
    }

    /// ADR-0087: the Geometry Inspector's computed X comes from the canvas
    /// frame, which is mirrored; say so, because edits change authored values.
    static func computedSource(_ source: String, field: GeometryInspectorField, isMirrored: Bool) -> String {
        isMirrored && field == .x ? source + ", mirrored right to left" : source
    }

    /// Mirrors only for a shown language other than the default that reads
    /// right to left (`nil`, the default and unknown languages never mirror).
    static func isMirrored(showing preferred: SiteLocaleID?, in localization: SiteLocalization?) -> Bool {
        guard let localization, let id = SiteCanvasLanguage.shownLocale(preferred, in: localization) else { return false }
        return SiteTranslationInspection.isRightToLeft(id, in: localization)
    }

    /// `geometry` mirrored inside each parent, parents before children. A node
    /// without a frame keeps having none; a node whose parent has no frame
    /// (page roots) keeps its frame. Mirroring twice gives `geometry` back.
    static func mirrored(_ geometry: [NodeID: InsertionGeometry], page: DocumentPage,
                         breakpoint: ResponsiveBreakpoint, viewportWidth: Double?) -> [NodeID: InsertionGeometry] {
        guard !geometry.isEmpty else { return geometry }
        let nodesByID = Dictionary(page.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result = geometry
        var pending = Array(page.rootNodeIDs.reversed())
        var visited = Set<NodeID>()
        while let parentID = pending.popLast() {
            guard visited.insert(parentID).inserted, let parent = nodesByID[parentID] else { continue }
            let children = parent.childIDs.compactMap { nodesByID[$0] }
            pending.append(contentsOf: children.map(\.id).reversed())
            guard let before = geometry[parentID]?.frame, let after = result[parentID]?.frame else { continue }
            let rule = childRule(of: parent, children: children, page: page,
                                 breakpoint: breakpoint, viewportWidth: viewportWidth)
            for child in children {
                guard let frame = geometry[child.id]?.frame else { continue }
                let offset = frame.minX - before.minX
                let mirrors = rule.flow || (rule.navigation && CanonicalPageFlow.isNavigationLink(child))
                let x = after.minX + (mirrors ? before.size.width - offset - frame.size.width : offset)
                result[child.id] = InsertionGeometry(origin: WorldPoint(x: x, y: frame.minY), size: frame.size)
            }
        }
        return result
    }

    /// The same parents `DocumentPage.resolvedStructuralGeometry` lays out:
    /// not a natural-flow page frame, not an unstyled (absolute) Frame.
    private static func childRule(of parent: DocumentNode, children: [DocumentNode], page: DocumentPage,
                                  breakpoint: ResponsiveBreakpoint, viewportWidth: Double?) -> (flow: Bool, navigation: Bool) {
        let policy = ResolvedContainerLayoutPolicy.resolve(parent, children: children, breakpoint: breakpoint,
                                                          viewportWidth: viewportWidth)
        guard !policy.naturalFlow,
              parent.kind != .frame || DesignBoxStyleCommandRegistry.resolvedStyle(for: parent)?.padding != nil else {
            return (false, false)
        }
        let flow: Bool = switch parent.kind {
        case .section, .stack, .form, .frame, .grid: true
        case .text, .image, .button, .link, .component: false
        }
        let navigation = CanonicalPageChrome.navigationSettings(for: parent, page: page).map {
            $0.id == parent.id || !CanonicalPageChrome.isCustom($0)
        } ?? false
        return (flow, navigation)
    }
}

// MARK: - SF-1001 / SF-1002 CMS collections (OD-035, ADR-0071)

enum CollectionIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "collection"
}

enum CollectionFieldIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "collection-field"
}

enum CollectionItemIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "collection-item"
}

typealias CollectionID = StableIdentifier<CollectionIdentifierDomain>
typealias CollectionFieldID = StableIdentifier<CollectionFieldIdentifierDomain>
typealias CollectionItemID = StableIdentifier<CollectionItemIdentifierDomain>

/// OD-035: the field types of a local collection.
enum CollectionFieldType: String, Codable, CaseIterable, Sendable {
    case text, richText, number, date, image, reference

    var title: String {
        switch self {
        case .text: "Text"
        case .richText: "Rich Text"
        case .number: "Number"
        case .date: "Date"
        case .image: "Image"
        case .reference: "Reference"
        }
    }

    /// The type template expressions read. Images and references are bound
    /// directly, not through expressions.
    var expressionType: SiteExpressionType? {
        switch self {
        case .text, .richText: .text
        case .number: .number
        case .date: .date
        case .image, .reference: nil
        }
    }
}

/// One authored value. Rich text is stored as text: paragraphs separated by
/// a blank line, line breaks kept.
enum CollectionFieldValue: Codable, Equatable, Sendable {
    case text(String)
    case number(Double)
    case date(SiteExpressionDate)
    case image(AssetID)
    case reference(CollectionItemID)

    func matches(_ type: CollectionFieldType) -> Bool {
        switch (self, type) {
        case (.text, .text), (.text, .richText), (.number, .number), (.date, .date), (.image, .image), (.reference, .reference):
            return true
        default:
            return false
        }
    }

    /// Empty text counts as no value (required fields, `isEmpty`).
    var isEmpty: Bool {
        if case .text(let text) = self { return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return false
    }

    var expressionValue: SiteExpressionValue {
        switch self {
        case .text(let text): .text(text)
        case .number(let number): .number(number)
        case .date(let date): .date(date)
        case .image, .reference: .missing
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case type, value }
    private enum Kind: String, Codable { case text, number, date, image, reference }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .type) {
        case .text:
            self = .text(try values.decode(String.self, forKey: .value))
        case .number:
            let number = try values.decode(Double.self, forKey: .value)
            guard number.isFinite else {
                throw DecodingError.dataCorruptedError(forKey: .value, in: values, debugDescription: "Collection numbers must be finite.")
            }
            self = .number(number)
        case .date:
            self = .date(try values.decode(SiteExpressionDate.self, forKey: .value))
        case .image:
            self = .image(try values.decode(AssetID.self, forKey: .value))
        case .reference:
            self = .reference(try values.decode(CollectionItemID.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try values.encode(Kind.text, forKey: .type)
            try values.encode(text, forKey: .value)
        case .number(let number):
            try values.encode(Kind.number, forKey: .type)
            try values.encode(number, forKey: .value)
        case .date(let date):
            try values.encode(Kind.date, forKey: .type)
            try values.encode(date, forKey: .value)
        case .image(let asset):
            try values.encode(Kind.image, forKey: .type)
            try values.encode(asset, forKey: .value)
        case .reference(let item):
            try values.encode(Kind.reference, forKey: .type)
            try values.encode(item, forKey: .value)
        }
    }
}

struct CollectionField: Codable, Equatable, Identifiable, Sendable {
    /// Names a template cannot use for a field (built-in item and page values).
    static let reservedKeys: Set<String> = ["slug", "status", "id", "collection", "item", "page", "site"]
    let id: CollectionFieldID
    /// The name expressions use, e.g. `title` or `publishedOn`.
    var key: String
    var label: String
    var type: CollectionFieldType
    /// Published items must have a value.
    var isRequired: Bool
    /// The collection a reference field points into; nil for other types.
    var referencedCollectionID: CollectionID?

    init(id: CollectionFieldID = CollectionFieldID(), key: String, label: String, type: CollectionFieldType,
         isRequired: Bool = false, referencedCollectionID: CollectionID? = nil) {
        self.id = id
        self.key = key
        self.label = label
        self.type = type
        self.isRequired = isRequired
        self.referencedCollectionID = referencedCollectionID
    }

    /// Starts with a lowercase ASCII letter; then ASCII letters, digits or
    /// underscore; at most 40 bytes; not an expression keyword or reserved name.
    static func isValidKey(_ key: String) -> Bool {
        let bytes = Array(key.utf8)
        guard (1...40).contains(bytes.count), bytes[0] >= 97, bytes[0] <= 122,
              bytes.allSatisfy({ ($0 >= 97 && $0 <= 122) || ($0 >= 65 && $0 <= 90) || ($0 >= 48 && $0 <= 57) || $0 == 95 }),
              !SiteExpressionEngine.reservedWords.contains(key), !reservedKeys.contains(key) else { return false }
        return true
    }

    /// A valid, unused key made from a label ("Published On" → `publishedOn`).
    static func suggestedKey(for label: String, existing: Set<String>) -> String {
        let folded = label.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let words = folded.split(whereSeparator: { !($0.isASCII && ($0.isLetter || $0.isNumber)) }).map(String.init)
        var base = words.enumerated().map { entry in
            entry.offset == 0 ? entry.element.lowercased()
                : entry.element.prefix(1).uppercased() + entry.element.dropFirst().lowercased()
        }.joined()
        while let first = base.unicodeScalars.first, !(first.value >= 97 && first.value <= 122) { base.removeFirst() }
        base = String(base.prefix(36))
        if !isValidKey(base) { base = "field" }
        var candidate = base
        var suffix = 2
        while existing.contains(candidate) || !isValidKey(candidate) {
            candidate = base + String(suffix)
            suffix += 1
        }
        return candidate
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, key, label, type, isRequired, referencedCollectionID }

    init(from decoder: Decoder) throws {
        let actual = Set(try decoder.container(keyedBy: AnySiteForgeCodingKey.self).allKeys.map(\.stringValue))
        let base = Set(CodingKeys.allCases.map(\.stringValue)).subtracting([CodingKeys.referencedCollectionID.stringValue])
        guard actual == base || actual == base.union([CodingKeys.referencedCollectionID.stringValue]) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Current SiteForge schema requires an exact closed key set."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(CollectionFieldID.self, forKey: .id)
        key = try values.decode(String.self, forKey: .key)
        label = try values.decode(String.self, forKey: .label)
        type = try values.decode(CollectionFieldType.self, forKey: .type)
        isRequired = try values.decode(Bool.self, forKey: .isRequired)
        referencedCollectionID = actual.contains(CodingKeys.referencedCollectionID.stringValue)
            ? try values.decode(CollectionID.self, forKey: .referencedCollectionID) : nil
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(key, forKey: .key)
        try values.encode(label, forKey: .label)
        try values.encode(type, forKey: .type)
        try values.encode(isRequired, forKey: .isRequired)
        try values.encodeIfPresent(referencedCollectionID, forKey: .referencedCollectionID)
    }
}

enum CollectionItemStatus: String, Codable, CaseIterable, Sendable {
    case draft, published

    var title: String {
        switch self {
        case .draft: "Draft"
        case .published: "Published"
        }
    }
}

struct CollectionItemValue: Codable, Equatable, Sendable {
    let fieldID: CollectionFieldID
    var value: CollectionFieldValue

    init(fieldID: CollectionFieldID, value: CollectionFieldValue) {
        self.fieldID = fieldID
        self.value = value
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case fieldID, value }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fieldID = try values.decode(CollectionFieldID.self, forKey: .fieldID)
        value = try values.decode(CollectionFieldValue.self, forKey: .value)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(fieldID, forKey: .fieldID)
        try values.encode(value, forKey: .value)
    }
}

struct CollectionItem: Codable, Equatable, Identifiable, Sendable {
    let id: CollectionItemID
    /// The item's address segment, unique in its collection.
    var slug: String
    var status: CollectionItemStatus
    /// Sorted by field identity, at most one per field. An absent value is an
    /// empty field, distinct from an authored empty text.
    var values: [CollectionItemValue]

    init(id: CollectionItemID = CollectionItemID(), slug: String, status: CollectionItemStatus = .draft,
         values: [CollectionItemValue] = []) {
        self.id = id
        self.slug = slug
        self.status = status
        self.values = values.sorted { $0.fieldID.description < $1.fieldID.description }
    }

    func value(for field: CollectionFieldID) -> CollectionFieldValue? {
        values.first { $0.fieldID == field }?.value
    }

    mutating func setValue(_ value: CollectionFieldValue?, for field: CollectionFieldID) {
        values.removeAll { $0.fieldID == field }
        if let value { values.append(CollectionItemValue(fieldID: field, value: value)) }
        values.sort { $0.fieldID.description < $1.fieldID.description }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, slug, status, values }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(CollectionItemID.self, forKey: .id)
        slug = try container.decode(String.self, forKey: .slug)
        status = try container.decode(CollectionItemStatus.self, forKey: .status)
        values = try container.decode([CollectionItemValue].self, forKey: .values)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(slug, forKey: .slug)
        try container.encode(status, forKey: .status)
        try container.encode(values, forKey: .values)
    }
}

/// Collection and item address segments: lowercase ASCII letters, digits and
/// single hyphens, 1–64 bytes, no leading or trailing hyphen.
enum CollectionSlug {
    static func isValid(_ slug: String) -> Bool {
        let bytes = Array(slug.utf8)
        guard (1...64).contains(bytes.count), bytes[0] != 45, bytes[bytes.count - 1] != 45, !slug.contains("--") else {
            return false
        }
        return bytes.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 }
    }

    static func make(from text: String, fallback: String = "item") -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var result = ""
        for scalar in folded.unicodeScalars {
            let value = scalar.value
            if (value >= 97 && value <= 122) || (value >= 48 && value <= 57) {
                result.unicodeScalars.append(scalar)
            } else if (value >= 65 && value <= 90), let lower = Unicode.Scalar(value + 32) {
                result.unicodeScalars.append(lower)
            } else if !result.isEmpty, !result.hasSuffix("-") {
                result.append("-")
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        result = String(result.prefix(56))
        while result.hasSuffix("-") { result.removeLast() }
        return isValid(result) ? result : fallback
    }

    static func unique(_ base: String, existing: Set<String>) -> String {
        guard existing.contains(base) else { return base }
        var suffix = 2
        while existing.contains("\(base)-\(suffix)") { suffix += 1 }
        return "\(base)-\(suffix)"
    }
}

struct ContentCollection: Codable, Equatable, Identifiable, Sendable {
    static let maximumFields = 64
    static let maximumItems = 10_000
    static let maximumTextBytes = 65_536
    let id: CollectionID
    var name: String
    /// The address segment template pages use, e.g. `blog` for `/blog/<item>`.
    var slug: String
    var fields: [CollectionField]
    var items: [CollectionItem]
    /// SF-1003: the page every published item is built from; nil when the
    /// collection has no item pages. Stored only when present.
    var template: CollectionTemplate?
    /// SF-1003-002: pages that repeat a layer for this collection's items.
    /// Stored only when there is at least one.
    var lists: [CollectionList]

    init(id: CollectionID = CollectionID(), name: String, slug: String,
         fields: [CollectionField] = [], items: [CollectionItem] = [], template: CollectionTemplate? = nil,
         lists: [CollectionList] = []) {
        self.id = id
        self.name = name
        self.slug = slug
        self.fields = fields
        self.items = items
        self.template = template
        self.lists = lists
    }

    func field(_ id: CollectionFieldID) -> CollectionField? { fields.first { $0.id == id } }

    /// SF-1004: what a template expression may read for one item: `slug`,
    /// every text, rich text, number and date field by key, and for each
    /// reference field `key.slug` plus the referenced collection's fields.
    func expressionSchema(in collections: [ContentCollection]) -> SiteExpressionSchema {
        var schema: [String: SiteExpressionType] = ["slug": .text]
        for field in fields {
            if let type = field.type.expressionType { schema[field.key] = type }
            guard field.type == .reference,
                  let target = collections.first(where: { $0.id == field.referencedCollectionID }) else { continue }
            schema[field.key + ".slug"] = .text
            for nested in target.fields {
                if let type = nested.type.expressionType { schema[field.key + "." + nested.key] = type }
            }
        }
        return SiteExpressionSchema(schema)
    }

    /// The values of one item for `expressionSchema`. Missing references and
    /// empty fields are missing values.
    func expressionContext(for item: CollectionItem, in collections: [ContentCollection]) -> SiteExpressionContext {
        var values: [String: SiteExpressionValue] = ["slug": .text(item.slug)]
        for field in fields {
            guard let value = item.value(for: field.id) else { continue }
            if field.type.expressionType != nil { values[field.key] = value.expressionValue }
            guard field.type == .reference, case .reference(let targetID) = value,
                  let target = collections.first(where: { $0.id == field.referencedCollectionID }),
                  let targetItem = target.items.first(where: { $0.id == targetID }) else { continue }
            values[field.key + ".slug"] = .text(targetItem.slug)
            for nested in target.fields where nested.type.expressionType != nil {
                if let nestedValue = targetItem.value(for: nested.id) { values[field.key + "." + nested.key] = nestedValue.expressionValue }
            }
        }
        return SiteExpressionContext(values)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, name, slug, fields, items, template, lists }

    init(from decoder: Decoder) throws {
        let actual = Set(try decoder.container(keyedBy: AnySiteForgeCodingKey.self).allKeys.map(\.stringValue))
        let optional: Set<String> = [CodingKeys.template.stringValue, CodingKeys.lists.stringValue]
        let base = Set(CodingKeys.allCases.map(\.stringValue)).subtracting(optional)
        guard base.isSubset(of: actual), actual.subtracting(base).isSubset(of: optional) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Current SiteForge schema requires an exact closed key set."))
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(CollectionID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        slug = try container.decode(String.self, forKey: .slug)
        fields = try container.decode([CollectionField].self, forKey: .fields)
        items = try container.decode([CollectionItem].self, forKey: .items)
        // Present means a template: an explicit null is refused, not read as none.
        template = actual.contains(CodingKeys.template.stringValue) ? try container.decode(CollectionTemplate.self, forKey: .template) : nil
        lists = actual.contains(CodingKeys.lists.stringValue) ? try container.decode([CollectionList].self, forKey: .lists) : []
        // No lists are stored by omitting the key, so there is one stored form.
        guard !actual.contains(CodingKeys.lists.stringValue) || !lists.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "An empty set of collection lists is stored by omitting it."))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(slug, forKey: .slug)
        try container.encode(fields, forKey: .fields)
        try container.encode(items, forKey: .items)
        try container.encodeIfPresent(template, forKey: .template)
        if !lists.isEmpty { try container.encode(lists, forKey: .lists) }
    }
}

/// SF-1001-004: one reason a collection draft cannot be committed, located by
/// stable identity. Messages name fields and rules, never values.
struct CollectionIssue: Hashable, Sendable {
    enum Kind: String, Sendable {
        case tooManyCollections, duplicateIdentity, name, duplicateName, slug, duplicateSlug
        case tooManyFields, fieldLabel, fieldKey, duplicateFieldKey, reference
        case tooManyItems, itemSlug, duplicateItemSlug, unknownField, duplicateValue, valueType, textTooLong, requiredMissing
        case template, duplicateTemplatePage, list, duplicateListLayer
    }

    let kind: Kind
    let collectionID: CollectionID
    var fieldID: CollectionFieldID?
    var itemID: CollectionItemID?

    var message: String {
        switch kind {
        case .tooManyCollections: "A project can have at most \(CanonicalCollections.maximumCollections) collections."
        case .duplicateIdentity: "Two collections, fields or items share an identity."
        case .name: "A collection needs a name of at most 128 bytes without leading or trailing spaces."
        case .duplicateName: "Another collection already has this name."
        case .slug: "The collection address must use lowercase letters, digits and single hyphens (at most 64)."
        case .duplicateSlug: "Another collection already uses this address."
        case .tooManyFields: "A collection can have at most \(ContentCollection.maximumFields) fields."
        case .fieldLabel: "A field needs a label of at most 128 bytes without leading or trailing spaces."
        case .fieldKey: "A field name must start with a lowercase letter and use only letters, digits or _ (at most 40); slug, status, id, collection, item, page, site, and, or, not, true and false are reserved."
        case .duplicateFieldKey: "Another field in this collection already uses this name."
        case .reference: "A reference field must point to an existing collection; other fields cannot."
        case .template: "The template has more than \(CollectionTemplate.maximumBindings) bindings, two bindings for one layer, or a binding without its expression or image field."
        case .duplicateTemplatePage: "Another collection already uses this page as its template."
        case .list: "A collection can have at most \(CollectionList.maximumListsPerCollection) lists. Each needs 1 to \(CollectionList.maximumPageSize) items per page, a limit of 1 to \(ContentCollection.maximumItems) when set, Previous and Next layers that differ from each other and from the repeated layer, and at most \(CollectionTemplate.maximumBindings) bindings, one per layer, each with its expression or image field."
        case .duplicateListLayer: "Another list already repeats this layer."
        case .tooManyItems: "A collection can have at most \(ContentCollection.maximumItems) items."
        case .itemSlug: "The item address must use lowercase letters, digits and single hyphens (at most 64)."
        case .duplicateItemSlug: "Another item in this collection already uses this address."
        case .unknownField: "An item has a value for a field that no longer exists."
        case .duplicateValue: "An item has two values for one field."
        case .valueType: "An item value does not match its field type."
        case .textTooLong: "A text value is longer than 64 KB or contains a NUL character."
        case .requiredMissing: "A published item is missing a required field. Fill it in or keep the item as a draft."
        }
    }
}

/// SF-1001-001/003/004: the document-level collection rules.
enum CanonicalCollections {
    static let maximumCollections = 100
    /// Collections are stored from document schema 27 (unreleased).
    static let documentSchema = 27

    static func issues(_ collections: [ContentCollection]) -> [CollectionIssue] {
        var result: [CollectionIssue] = []
        if collections.count > maximumCollections, let first = collections.first {
            result.append(CollectionIssue(kind: .tooManyCollections, collectionID: first.id))
        }
        var seenCollectionIDs = Set<CollectionID>(), seenNames = Set<String>(), seenSlugs = Set<String>()
        let collectionIDs = Set(collections.map(\.id))
        var seenTemplatePages = Set<PageID>()
        var seenListLayers = Set<NodeID>()
        for collection in collections {
            func add(_ kind: CollectionIssue.Kind, field: CollectionFieldID? = nil, item: CollectionItemID? = nil) {
                result.append(CollectionIssue(kind: kind, collectionID: collection.id, fieldID: field, itemID: item))
            }
            if !seenCollectionIDs.insert(collection.id).inserted { add(.duplicateIdentity) }
            if !WebsiteMetadata.validText(collection.name, maximumBytes: 128) {
                add(.name)
            } else if !seenNames.insert(collection.name.lowercased()).inserted {
                add(.duplicateName)
            }
            if !CollectionSlug.isValid(collection.slug) {
                add(.slug)
            } else if !seenSlugs.insert(collection.slug).inserted {
                add(.duplicateSlug)
            }
            if collection.fields.count > ContentCollection.maximumFields { add(.tooManyFields) }
            if let template = collection.template {
                if !template.isStructurallyValid { add(.template) }
                if !seenTemplatePages.insert(template.pageID).inserted { add(.duplicateTemplatePage) }
            }
            if collection.lists.count > CollectionList.maximumListsPerCollection
                || !collection.lists.allSatisfy(\.isStructurallyValid) { add(.list) }
            for list in collection.lists where !seenListLayers.insert(list.repeatedNodeID).inserted { add(.duplicateListLayer) }
            var fieldIDs = Set<CollectionFieldID>(), keys = Set<String>()
            for field in collection.fields {
                if !fieldIDs.insert(field.id).inserted { add(.duplicateIdentity, field: field.id) }
                if !WebsiteMetadata.validText(field.label, maximumBytes: 128) { add(.fieldLabel, field: field.id) }
                if !CollectionField.isValidKey(field.key) {
                    add(.fieldKey, field: field.id)
                } else if !keys.insert(field.key).inserted {
                    add(.duplicateFieldKey, field: field.id)
                }
                let pointsToCollection = field.referencedCollectionID.map { collectionIDs.contains($0) } ?? false
                let referenceIsValid = field.type == .reference ? pointsToCollection : field.referencedCollectionID == nil
                if !referenceIsValid { add(.reference, field: field.id) }
            }
            if collection.items.count > ContentCollection.maximumItems { add(.tooManyItems) }
            var itemIDs = Set<CollectionItemID>(), itemSlugs = Set<String>()
            for item in collection.items {
                if !itemIDs.insert(item.id).inserted { add(.duplicateIdentity, item: item.id) }
                if !CollectionSlug.isValid(item.slug) {
                    add(.itemSlug, item: item.id)
                } else if !itemSlugs.insert(item.slug).inserted {
                    add(.duplicateItemSlug, item: item.id)
                }
                var valueFields = Set<CollectionFieldID>()
                for entry in item.values {
                    if !valueFields.insert(entry.fieldID).inserted { add(.duplicateValue, field: entry.fieldID, item: item.id) }
                    guard let field = collection.field(entry.fieldID) else {
                        add(.unknownField, field: entry.fieldID, item: item.id)
                        continue
                    }
                    if !entry.value.matches(field.type) { add(.valueType, field: field.id, item: item.id) }
                    if case .text(let text) = entry.value, text.utf8.count > ContentCollection.maximumTextBytes || text.contains("\u{0}") {
                        add(.textTooLong, field: field.id, item: item.id)
                    }
                }
                if item.values.map(\.fieldID.description) != item.values.map(\.fieldID.description).sorted() {
                    add(.duplicateValue, item: item.id)
                }
                if item.status == .published {
                    for field in collection.fields where field.isRequired {
                        if item.value(for: field.id).map({ $0.isEmpty }) ?? true { add(.requiredMissing, field: field.id, item: item.id) }
                    }
                }
            }
        }
        return result
    }

    static func usesAsset(_ asset: AssetID, in collections: [ContentCollection]) -> Bool {
        collections.contains { collection in
            collection.items.contains { item in item.values.contains { $0.value == .image(asset) } }
        }
    }

    /// Fields in any collection that reference `collection` (deleting it is refused while any exist).
    static func referencingFields(to collection: CollectionID, in collections: [ContentCollection]) -> [CollectionField] {
        collections.filter { $0.id != collection }.flatMap(\.fields).filter { $0.referencedCollectionID == collection }
    }

    /// SF-1001 critical invariant: how many items lose a value if `field` is removed.
    static func itemsWithValue(for field: CollectionFieldID, in collection: ContentCollection) -> Int {
        collection.items.filter { $0.value(for: field) != nil }.count
    }

    /// Items in other collections whose reference points at `item`.
    static func referencesTo(item: CollectionItemID, in collections: [ContentCollection]) -> Int {
        collections.reduce(0) { count, collection in
            count + collection.items.filter { candidate in candidate.values.contains { $0.value == .reference(item) } }.count
        }
    }
}

/// SF-1003 (OD-035, ADR-0072): what a binding fills on its template node.
enum CollectionBindingTarget: String, Codable, CaseIterable, Sendable {
    /// The text of a Text node, from an expression rendered as text.
    case text
    /// The picture of an Image node, from an image field.
    case image
    /// A Link or Button layer that opens the item's own page (SF-1003 lists).
    case link
}

/// SF-1003-001: one authored link from a template node to item data. A node
/// without a binding keeps its authored content on every item page
/// (omitted); an expression may supply its own fallback with `??`
/// (defaulted); otherwise the item's value is shown (authored). Text uses an
/// expression, an image uses an image field; never both.
struct CollectionBinding: Codable, Hashable, Sendable {
    let nodeID: NodeID
    let target: CollectionBindingTarget
    var expression: SiteExpression?
    var fieldID: CollectionFieldID?

    init(nodeID: NodeID, target: CollectionBindingTarget, expression: SiteExpression? = nil, fieldID: CollectionFieldID? = nil) {
        self.nodeID = nodeID
        self.target = target
        self.expression = expression
        self.fieldID = fieldID
    }

    static func text(_ node: NodeID, _ expression: SiteExpression) -> Self {
        Self(nodeID: node, target: .text, expression: expression)
    }

    static func image(_ node: NodeID, field: CollectionFieldID) -> Self {
        Self(nodeID: node, target: .image, fieldID: field)
    }

    static func link(_ node: NodeID) -> Self {
        Self(nodeID: node, target: .link)
    }

    var isWellFormed: Bool {
        switch target {
        case .text: expression != nil && fieldID == nil
        case .image: expression == nil && fieldID != nil
        case .link: expression == nil && fieldID == nil
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case nodeID, target, expression, fieldID }

    init(from decoder: Decoder) throws {
        let actual = Set(try decoder.container(keyedBy: AnySiteForgeCodingKey.self).allKeys.map(\.stringValue))
        let base: Set<String> = [CodingKeys.nodeID.stringValue, CodingKeys.target.stringValue]
        guard actual == base || actual == base.union([CodingKeys.expression.stringValue])
                || actual == base.union([CodingKeys.fieldID.stringValue]) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Current SiteForge schema requires an exact closed key set."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try values.decode(NodeID.self, forKey: .nodeID)
        target = try values.decode(CollectionBindingTarget.self, forKey: .target)
        expression = actual.contains(CodingKeys.expression.stringValue) ? try values.decode(SiteExpression.self, forKey: .expression) : nil
        fieldID = actual.contains(CodingKeys.fieldID.stringValue) ? try values.decode(CollectionFieldID.self, forKey: .fieldID) : nil
        guard isWellFormed else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "A text binding needs an expression, an image binding an image field, and an item link neither."))
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(nodeID, forKey: .nodeID)
        try values.encode(target, forKey: .target)
        try values.encodeIfPresent(expression, forKey: .expression)
        try values.encodeIfPresent(fieldID, forKey: .fieldID)
    }
}

/// SF-1003-001/002: the page a collection uses as the design of every item
/// page. Each published item becomes `/<collection address>/<item address>`;
/// drafts are never written. Bindings to nodes, fields or pages that no longer
/// exist are kept (the author's intent) and reported, never silently dropped.
struct CollectionTemplate: Codable, Equatable, Sendable {
    static let maximumBindings = 256
    var pageID: PageID
    /// The item page's name for titles; nil uses the item's first text value or its address.
    var title: SiteExpression?
    /// Sorted by node identity, then target.
    var bindings: [CollectionBinding]

    init(pageID: PageID, title: SiteExpression? = nil, bindings: [CollectionBinding] = []) {
        self.pageID = pageID
        self.title = title
        self.bindings = bindings
    }

    func binding(for node: NodeID, target: CollectionBindingTarget) -> CollectionBinding? {
        bindings.first { $0.nodeID == node && $0.target == target }
    }

    var isStructurallyValid: Bool {
        guard bindings.count <= Self.maximumBindings, bindings.allSatisfy(\.isWellFormed) else { return false }
        let keys = bindings.map { $0.nodeID.description + "/" + $0.target.rawValue }
        return Set(keys).count == keys.count && keys == keys.sorted()
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case pageID, title, bindings }

    init(from decoder: Decoder) throws {
        let actual = Set(try decoder.container(keyedBy: AnySiteForgeCodingKey.self).allKeys.map(\.stringValue))
        let base: Set<String> = [CodingKeys.pageID.stringValue, CodingKeys.bindings.stringValue]
        guard actual == base || actual == base.union([CodingKeys.title.stringValue]) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Current SiteForge schema requires an exact closed key set."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pageID = try values.decode(PageID.self, forKey: .pageID)
        title = actual.contains(CodingKeys.title.stringValue) ? try values.decode(SiteExpression.self, forKey: .title) : nil
        bindings = try values.decode([CollectionBinding].self, forKey: .bindings)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(pageID, forKey: .pageID)
        try values.encodeIfPresent(title, forKey: .title)
        try values.encode(bindings, forKey: .bindings)
    }
}

/// SF-1003-004: why part of a template will not be used at export. Located by
/// identity; messages name fields and rules, never item values.
struct CollectionTemplateFinding: Hashable, Sendable {
    enum Kind: String, Sendable {
        case missingPage, unsupportedPage, missingNode, unsupportedNode, expression, imageField, routeCollision, noPublishedItems
        // SF-1003-002 lists.
        case listPage, listLayerMissing, listNeedsFlow, listOverlap, listFilter, listSortField, paginationControl, noItemPages
    }

    let kind: Kind
    let collectionID: CollectionID
    var nodeID: NodeID?
    var itemID: CollectionItemID?
    /// The expression error, for `.expression` and `.listFilter` (names fields, functions and types only).
    var detail: String?
    /// The list (its repeated layer) a finding belongs to; nil for templates.
    var listID: NodeID?

    var message: String {
        switch kind {
        case .missingPage: listID == nil ? "The template page no longer exists. Choose another page in Collections > Template."
            : "The page of a list no longer exists. The list is kept, but not written."
        case .unsupportedPage: "The Home page, the Not Found page and components cannot be templates. Choose a regular page."
        case .missingNode: "A binding points to a layer that is no longer on the template page or inside the list's repeated layer. It is kept, but not used."
        case .unsupportedNode: "Text bindings need a Text layer, image bindings need an Image layer that already shows a picture, and item links need a Link or Button layer."
        case .expression: "A binding cannot be used: \(detail ?? "the expression is not valid")."
        case .imageField: "An image binding needs an image field of this collection."
        case .routeCollision: listID == nil ? "An item page would use the same address as another page. Change the item or page address."
            : "A later page of a list (…/page/2 and on) would use the same address as another page. Change the page address or show more items per page."
        case .noPublishedItems: "No item is published, so no item pages are written and links to the template page do not open."
        case .listPage: "Lists can be on Home or a regular page, not on the Not Found page, a component or a page used as an item template."
        case .listLayerMissing: "The layer a list repeats is no longer on its page. The list is kept, but not written."
        case .listNeedsFlow: "The repeated layer must be directly inside a Stack or Grid, so its copies line up instead of overlapping."
        case .listOverlap: "Another list on this page already repeats this layer or a layer around it. Repeat layers that sit side by side."
        case .listFilter: "The list filter is not used, so every published item is listed: \(detail ?? "it must give True or False")."
        case .listSortField: "The list is ordered by a field that no longer exists or cannot be ordered (images and references). Items keep the Items order."
        case .paginationControl: "Previous and Next must be Link or Button layers on the list's page, outside every repeated layer. This one is left as designed."
        case .noItemPages: "A layer is set to open each item's page, but this collection has no template page, so the layer keeps its own link."
        }
    }
}

/// SF-1003: how template pages become one static page per published item.
/// Pure and deterministic: the same document always gives the same pages.
enum CollectionTemplates {
    static let requirementID = "SF-1003-001"
    static let textKey = "content.text"
    static let imageKey = CanonicalImageStyle.namespace + "assetID"

    struct OutputPage: Equatable, Sendable {
        let page: DocumentPage
        /// The template itself, or the first item page of a template. Shared
        /// style output is taken once from these pages.
        let isPrimary: Bool
        let itemID: CollectionItemID?
        /// The written page number of a page with lists (1 at its own address).
        var listPageNumber: Int? = nil
    }

    static func itemRoute(_ collection: ContentCollection, _ item: CollectionItem) -> PageRoute {
        PageRoute(rawValue: "/" + collection.slug + "/" + item.slug)
    }

    static func publishedItems(_ collection: ContentCollection) -> [CollectionItem] {
        collection.items.filter { $0.status == .published }
    }

    /// The template page when it exists and is a regular page.
    static func activePage(for collection: ContentCollection, in document: CanonicalDocument) -> DocumentPage? {
        guard let template = collection.template,
              let page = document.pages.first(where: { $0.id == template.pageID }), page.role == .standard else { return nil }
        return page
    }

    /// Pages whose output is replaced by item pages.
    static func templatePageIDs(_ document: CanonicalDocument) -> Set<PageID> {
        Set(document.collections.compactMap { activePage(for: $0, in: document)?.id })
    }

    /// Links to a template page open its first published item.
    static func linkTargets(_ document: CanonicalDocument) -> [PageID: PageRoute] {
        var result: [PageID: PageRoute] = [:]
        for collection in document.collections {
            guard let page = activePage(for: collection, in: document),
                  let first = publishedItems(collection).first else { continue }
            result[page.id] = itemRoute(collection, first)
        }
        return result
    }

    /// The link identity of one item's page. Never a document page: links
    /// that open an item use it, and the build maps it to the item's address.
    static func itemLinkPageID(_ collection: ContentCollection, _ item: CollectionItem) -> PageID {
        PageID(DocumentPage.deterministicUUID(namespace: item.id.rawValue, label: "collection-item-page:" + collection.id.description))
    }

    /// Every written item page by its link identity.
    static func itemLinkRoutes(_ document: CanonicalDocument) -> [PageID: PageRoute] {
        var result: [PageID: PageRoute] = [:]
        for collection in document.collections where activePage(for: collection, in: document) != nil {
            for item in publishedItems(collection) { result[itemLinkPageID(collection, item)] = itemRoute(collection, item) }
        }
        return result
    }

    fileprivate struct Compiled {
        var title: SiteExpressionProgram?
        var text: [NodeID: SiteExpressionProgram] = [:]
        var images: [NodeID: CollectionFieldID] = [:]
        /// Link or Button layers that open the item's own page.
        var links: Set<NodeID> = []
    }

    private static func compile(_ collection: ContentCollection, page: DocumentPage, document: CanonicalDocument,
                                findings: inout [CollectionTemplateFinding]) -> Compiled {
        var compiled = Compiled()
        guard let template = collection.template else { return compiled }
        let schema = collection.expressionSchema(in: document.collections)
        if let title = template.title {
            do { compiled.title = try title.check(schema) } catch {
                findings.append(.init(kind: .expression, collectionID: collection.id, detail: error.localizedDescription))
            }
        }
        compileBindings(template.bindings, into: &compiled, collection: collection, nodes: page.nodes, schema: schema,
                        linksAvailable: true, listID: nil, findings: &findings)
        return compiled
    }

    /// Checks each binding against the layer it names among `candidates`
    /// (the template page, or a list's repeated layer). Unusable bindings are
    /// reported and skipped; the layer keeps its designed content.
    fileprivate static func compileBindings(_ bindings: [CollectionBinding], into compiled: inout Compiled,
                                            collection: ContentCollection, nodes candidates: [DocumentNode],
                                            schema: SiteExpressionSchema, linksAvailable: Bool, listID: NodeID?,
                                            findings: inout [CollectionTemplateFinding]) {
        let nodes = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var reportedNoItemPages = false
        for binding in bindings {
            guard let node = nodes[binding.nodeID] else {
                findings.append(.init(kind: .missingNode, collectionID: collection.id, nodeID: binding.nodeID, listID: listID))
                continue
            }
            switch binding.target {
            case .text:
                guard node.kind == .text else {
                    findings.append(.init(kind: .unsupportedNode, collectionID: collection.id, nodeID: node.id, listID: listID))
                    continue
                }
                guard let expression = binding.expression else { continue }
                do { compiled.text[node.id] = try expression.check(schema) } catch {
                    findings.append(.init(kind: .expression, collectionID: collection.id, nodeID: node.id,
                                          detail: error.localizedDescription, listID: listID))
                }
            case .image:
                guard node.kind == .image, node.properties.contains(where: { $0.key.rawValue == imageKey }) else {
                    findings.append(.init(kind: .unsupportedNode, collectionID: collection.id, nodeID: node.id, listID: listID))
                    continue
                }
                guard let fieldID = binding.fieldID, collection.field(fieldID)?.type == .image else {
                    findings.append(.init(kind: .imageField, collectionID: collection.id, nodeID: node.id, listID: listID))
                    continue
                }
                compiled.images[node.id] = fieldID
            case .link:
                guard node.kind.isLinkControl else {
                    findings.append(.init(kind: .unsupportedNode, collectionID: collection.id, nodeID: node.id, listID: listID))
                    continue
                }
                guard linksAvailable else {
                    if !reportedNoItemPages {
                        findings.append(.init(kind: .noItemPages, collectionID: collection.id, nodeID: node.id, listID: listID))
                    }
                    reportedNoItemPages = true
                    continue
                }
                compiled.links.insert(node.id)
            }
        }
    }

    /// SF-1003-004: everything that keeps a template, or part of it, from being used.
    static func findings(_ document: CanonicalDocument) -> [CollectionTemplateFinding] {
        var result: [CollectionTemplateFinding] = []
        let templatePages = templatePageIDs(document)
        let otherRoutes = Set(document.pages.filter { $0.role != .componentDefinition && !templatePages.contains($0.id) }
            .map(\.route.rawValue))
        for collection in document.collections {
            guard let template = collection.template else { continue }
            guard let page = document.pages.first(where: { $0.id == template.pageID }) else {
                result.append(.init(kind: .missingPage, collectionID: collection.id))
                continue
            }
            guard page.role == .standard else {
                result.append(.init(kind: .unsupportedPage, collectionID: collection.id))
                continue
            }
            _ = compile(collection, page: page, document: document, findings: &result)
            let published = publishedItems(collection)
            if published.isEmpty { result.append(.init(kind: .noPublishedItems, collectionID: collection.id)) }
            for item in published where otherRoutes.contains(itemRoute(collection, item).rawValue) {
                result.append(.init(kind: .routeCollision, collectionID: collection.id, itemID: item.id))
            }
        }
        result += CollectionLists.findings(document)
        return result
    }

    /// One item's page: the template's design, the item's address, and every
    /// usable binding filled from the item. Identities are the template's.
    static func itemPage(_ page: DocumentPage, collection: ContentCollection, item: CollectionItem,
                         document: CanonicalDocument) -> DocumentPage {
        var ignored: [CollectionTemplateFinding] = []
        return boundPage(page, collection: collection, item: item, document: document,
                         compiled: compile(collection, page: page, document: document, findings: &ignored))
    }

    private static func boundPage(_ page: DocumentPage, collection: ContentCollection, item: CollectionItem,
                                  document: CanonicalDocument, compiled: Compiled) -> DocumentPage {
        let context = collection.expressionContext(for: item, in: document.collections)
        let assets = Set(document.imageAssets.map(\.id))
        var result = page
        result.route = itemRoute(collection, item)
        let title = compiled.title.map { SiteExpressionEngine.evaluate($0, context: context).value.renderedText }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        result.name = title.isEmpty ? CollectionEditing.displayTitle(item, in: collection) : title
        result.nodes = page.nodes.map { node in
            var copy = node
            bind(&copy, source: node.id, compiled: compiled, collection: collection, item: item, context: context, assets: assets)
            return copy
        }
        return result
    }

    /// Fills one layer, or a list's copy of the layer `source`, from an item.
    fileprivate static func bind(_ node: inout DocumentNode, source: NodeID, compiled: Compiled, collection: ContentCollection,
                                 item: CollectionItem, context: SiteExpressionContext, assets: Set<AssetID>) {
        if let program = compiled.text[source] {
            let text = SiteExpressionEngine.evaluate(program, context: context).value.renderedText
            setProperty(textKey, .string(text), on: &node)
        }
        if let fieldID = compiled.images[source], case .image(let asset)? = item.value(for: fieldID), assets.contains(asset) {
            setProperty(imageKey, .string(asset.description), on: &node)
        }
        if compiled.links.contains(source) {
            setLink(.page(itemLinkPageID(collection, item)), on: &node)
        }
    }

    /// Replaces a Link or Button layer's destination; its label and new-window choice stay.
    fileprivate static func setLink(_ target: CanonicalLinkTarget, on node: inout DocumentNode) {
        let keys = Set(["kind", "pageID", "nodeID", "url"].map { CanonicalLinkTarget.namespace + $0 })
        node.properties.removeAll { keys.contains($0.key.rawValue) }
        for (key, value) in target.properties { setProperty(key, value, on: &node) }
    }

    private static func setProperty(_ key: String, _ value: PropertyValue, on node: inout DocumentNode) {
        if let index = node.properties.firstIndex(where: { $0.key.rawValue == key }) {
            node.properties[index].value = value
            node.properties[index].origin = .authored
        } else {
            node.properties.append(NodeProperty(key: PropertyKey(rawValue: key), value: value))
        }
    }

    /// SF-1003-002/006: the pages a build writes. `pages` are the build's
    /// (component-resolved) pages; each active template is replaced by one
    /// page per published item, in item order.
    static func outputPages(_ pages: [DocumentPage], document: CanonicalDocument) -> [OutputPage] {
        var templates: [PageID: ContentCollection] = [:]
        for collection in document.collections {
            if let page = activePage(for: collection, in: document), templates[page.id] == nil { templates[page.id] = collection }
        }
        // SF-1003-002: a page with lists is written once per page of its longest list.
        var ignoredListFindings: [CollectionTemplateFinding] = []
        let listed = CollectionLists.placements(document, pages: pages, findings: &ignoredListFindings)
        var result: [OutputPage] = []
        for page in pages {
            guard let collection = templates[page.id] else {
                if let placements = listed[page.id] {
                    result += CollectionLists.outputPages(page, placements: placements, document: document)
                } else {
                    result.append(.init(page: page, isPrimary: true, itemID: nil))
                }
                continue
            }
            var ignored: [CollectionTemplateFinding] = []
            let compiled = compile(collection, page: page, document: document, findings: &ignored)
            for (index, item) in publishedItems(collection).enumerated() {
                result.append(.init(page: boundPage(page, collection: collection, item: item, document: document, compiled: compiled),
                                    isPrimary: index == 0, itemID: item.id))
            }
        }
        return result
    }

    /// SF-1003-008: sanitized record of one template operation.
    static func diagnostic(_ operation: String, document: CanonicalDocument, startedAt start: Date) -> CollectionEditDiagnostic {
        let found = findings(document)
        return CollectionEditDiagnostic(requirementID: requirementID, operation: operation,
            collectionIdentifiers: document.collections.filter { $0.template != nil }.map(\.id.description).sorted(),
            itemCount: document.collections.filter { activePage(for: $0, in: document) != nil }
                .reduce(0) { $0 + publishedItems($1).count },
            durationMilliseconds: max(0, Int(Date().timeIntervalSince(start) * 1_000)),
            failureCategory: found.first?.kind.rawValue ?? "none")
    }
}

/// SF-1003-002 (OD-035, ADR-0072): the order a list writes its items in.
enum CollectionListSortDirection: String, Codable, CaseIterable, Sendable {
    case ascending, descending

    var title: String {
        switch self {
        case .ascending: "Ascending"
        case .descending: "Descending"
        }
    }
}

/// SF-1003-001/002: a page that repeats one of its layers once per item, such
/// as a blog index, a product grid or a team list. The page keeps its own
/// address; when more items match than fit, the rest are written as
/// `<address>/page/2`, `/page/3` and on. The repeated layer must sit directly
/// in a Stack or Grid so its copies flow instead of overlapping. Layers, pages
/// and fields that no longer exist are kept (the author's intent) and
/// reported, never silently dropped.
struct CollectionList: Codable, Equatable, Identifiable, Sendable {
    static let maximumListsPerCollection = 16
    static let maximumPageSize = 100
    static let defaultPageSize = 12
    var pageID: PageID
    /// The layer repeated for every item, with everything inside it. Also the list's identity.
    let repeatedNodeID: NodeID
    /// Only items for which this True or False expression is true; nil lists every published item.
    var filter: SiteExpression?
    /// The field items are ordered by; nil keeps the order of the Items list.
    var sortFieldID: CollectionFieldID?
    var sortDirection: CollectionListSortDirection
    /// At most this many items in total; nil lists every item that matches.
    var limit: Int?
    /// Items on each written page, 1–100.
    var pageSize: Int
    /// Link or Button layers outside the repeated layer that open the
    /// previous and the next page; left out where there is none.
    var previousNodeID: NodeID?
    var nextNodeID: NodeID?
    /// Bindings for layers inside the repeated layer, sorted by node identity, then target.
    var bindings: [CollectionBinding]

    var id: NodeID { repeatedNodeID }

    init(pageID: PageID, repeatedNodeID: NodeID, filter: SiteExpression? = nil, sortFieldID: CollectionFieldID? = nil,
         sortDirection: CollectionListSortDirection = .ascending, limit: Int? = nil,
         pageSize: Int = CollectionList.defaultPageSize, previousNodeID: NodeID? = nil, nextNodeID: NodeID? = nil,
         bindings: [CollectionBinding] = []) {
        self.pageID = pageID
        self.repeatedNodeID = repeatedNodeID
        self.filter = filter
        self.sortFieldID = sortFieldID
        self.sortDirection = sortDirection
        self.limit = limit
        self.pageSize = pageSize
        self.previousNodeID = previousNodeID
        self.nextNodeID = nextNodeID
        self.bindings = bindings
    }

    func binding(for node: NodeID, target: CollectionBindingTarget) -> CollectionBinding? {
        bindings.first { $0.nodeID == node && $0.target == target }
    }

    var isStructurallyValid: Bool {
        guard (1...Self.maximumPageSize).contains(pageSize),
              limit.map({ (1...ContentCollection.maximumItems).contains($0) }) ?? true,
              bindings.count <= CollectionTemplate.maximumBindings, bindings.allSatisfy(\.isWellFormed) else { return false }
        if let previousNodeID, previousNodeID == nextNodeID { return false }
        guard previousNodeID != repeatedNodeID, nextNodeID != repeatedNodeID else { return false }
        let keys = bindings.map { $0.nodeID.description + "/" + $0.target.rawValue }
        return Set(keys).count == keys.count && keys == keys.sorted()
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case pageID, repeatedNodeID, filter, sortFieldID, sortDirection, limit, pageSize, previousNodeID, nextNodeID, bindings
    }

    init(from decoder: Decoder) throws {
        let actual = Set(try decoder.container(keyedBy: AnySiteForgeCodingKey.self).allKeys.map(\.stringValue))
        let required = Set([CodingKeys.pageID, .repeatedNodeID, .sortDirection, .pageSize, .bindings].map(\.stringValue))
        guard required.isSubset(of: actual), actual.isSubset(of: Set(CodingKeys.allCases.map(\.stringValue))) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Current SiteForge schema requires an exact closed key set."))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func has(_ key: CodingKeys) -> Bool { actual.contains(key.stringValue) }
        pageID = try values.decode(PageID.self, forKey: .pageID)
        repeatedNodeID = try values.decode(NodeID.self, forKey: .repeatedNodeID)
        // Present means a value: an explicit null is refused, not read as none.
        filter = has(.filter) ? try values.decode(SiteExpression.self, forKey: .filter) : nil
        sortFieldID = has(.sortFieldID) ? try values.decode(CollectionFieldID.self, forKey: .sortFieldID) : nil
        sortDirection = try values.decode(CollectionListSortDirection.self, forKey: .sortDirection)
        limit = has(.limit) ? try values.decode(Int.self, forKey: .limit) : nil
        pageSize = try values.decode(Int.self, forKey: .pageSize)
        previousNodeID = has(.previousNodeID) ? try values.decode(NodeID.self, forKey: .previousNodeID) : nil
        nextNodeID = has(.nextNodeID) ? try values.decode(NodeID.self, forKey: .nextNodeID) : nil
        bindings = try values.decode([CollectionBinding].self, forKey: .bindings)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(pageID, forKey: .pageID)
        try values.encode(repeatedNodeID, forKey: .repeatedNodeID)
        try values.encodeIfPresent(filter, forKey: .filter)
        try values.encodeIfPresent(sortFieldID, forKey: .sortFieldID)
        try values.encode(sortDirection, forKey: .sortDirection)
        try values.encodeIfPresent(limit, forKey: .limit)
        try values.encode(pageSize, forKey: .pageSize)
        try values.encodeIfPresent(previousNodeID, forKey: .previousNodeID)
        try values.encodeIfPresent(nextNodeID, forKey: .nextNodeID)
        try values.encode(bindings, forKey: .bindings)
    }
}

/// SF-1003-003: which items a list shows, in which order and on how many
/// written pages, and the rules that decided it (counts and field names
/// only, never item values).
struct CollectionListResolution: Equatable, Sendable {
    let publishedCount: Int
    /// Published items the filter keeps (all of them without a usable filter).
    let matchingCount: Int
    /// After the filter, the order and the limit.
    let items: [CollectionItem]
    let pageSize: Int
    let explanation: [String]

    var pageCount: Int { max(1, (items.count + pageSize - 1) / pageSize) }

    /// The items on written page `number` (1-based); empty past the last page.
    func items(onPage number: Int) -> [CollectionItem] {
        let start = (number - 1) * pageSize
        guard number >= 1, start < items.count else { return [] }
        return Array(items[start..<min(items.count, start + pageSize)])
    }

    var summary: String {
        "Shows \(items.count) of \(publishedCount) published \(publishedCount == 1 ? "item" : "items") on \(pageCount) \(pageCount == 1 ? "page" : "pages")."
    }
}

/// SF-1003-002/003/006: how lists become written pages. Pure and
/// deterministic: the same document always gives the same pages. A copy of a
/// layer has the same identity at the same position on every page of a list,
/// so styles are written once, from the list's first page.
enum CollectionLists {
    static let requirementID = "SF-1003-002"
    /// Field types a list can be ordered by.
    static let sortableTypes: Set<CollectionFieldType> = [.text, .richText, .number, .date]

    fileprivate struct Placement {
        let collection: ContentCollection
        let list: CollectionList
        /// The repeated layer and everything inside it.
        let subtree: Set<NodeID>
        let compiled: CollectionTemplates.Compiled
        let resolution: CollectionListResolution
        /// Usable Previous and Next layers.
        let previousNodeID: NodeID?
        let nextNodeID: NodeID?
    }

    /// The address of written page `number` of a page: its own for page 1.
    static func pageRoute(_ route: PageRoute, number: Int) -> PageRoute {
        guard number > 1 else { return route }
        return PageRoute(rawValue: (route.rawValue == "/" ? "" : route.rawValue) + "/page/\(number)")
    }

    /// The link identity of written page `number` (the page itself for page 1).
    static func pageLinkID(_ page: PageID, number: Int) -> PageID {
        number > 1 ? PageID(DocumentPage.deterministicUUID(namespace: page.rawValue, label: "collection-list-page:\(number)")) : page
    }

    /// The identity of a layer's copy at position `slot` (0-based) on every
    /// written page; the first copy keeps the layer's own identity.
    static func copyID(_ node: NodeID, slot: Int) -> NodeID {
        slot > 0 ? NodeID(DocumentPage.deterministicUUID(namespace: node.rawValue, label: "collection-list-slot:\(slot)")) : node
    }

    /// A layer and every layer inside it.
    static func subtree(_ root: NodeID, in page: DocumentPage) -> Set<NodeID> {
        let nodes = Dictionary(page.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result = Set<NodeID>(), pending = [root]
        while let id = pending.popLast() {
            guard let node = nodes[id], result.insert(id).inserted else { continue }
            pending += node.childIDs
        }
        return result
    }

    /// SF-1003-003: published items only; then the filter (true keeps an
    /// item; false or missing leaves it out; an unusable filter is reported
    /// and every published item is kept); then the order (items without a
    /// value last in either direction, ties keep the Items order); then the
    /// limit; then pages of `pageSize`.
    static func resolve(_ list: CollectionList, collection: ContentCollection, collections: [ContentCollection],
                        findings: inout [CollectionTemplateFinding]) -> CollectionListResolution {
        let published = CollectionTemplates.publishedItems(collection)
        var explanation = ["\(published.count) published \(published.count == 1 ? "item" : "items"); drafts are never listed."]
        var items = published
        if let filter = list.filter {
            do {
                let program = try filter.check(collection.expressionSchema(in: collections))
                if program.resultType == .boolean {
                    items = published.filter {
                        SiteExpressionEngine.evaluate(program, context: collection.expressionContext(for: $0, in: collections)).value == .boolean(true)
                    }
                    explanation.append("The filter keeps \(items.count): items where it is true. False or missing results leave an item out.")
                } else {
                    findings.append(.init(kind: .listFilter, collectionID: collection.id, nodeID: list.repeatedNodeID,
                                          detail: "it gives \(program.resultType.title), not True or False", listID: list.id))
                    explanation.append("The filter is not used because it does not give True or False, so every published item is listed.")
                }
            } catch {
                findings.append(.init(kind: .listFilter, collectionID: collection.id, nodeID: list.repeatedNodeID,
                                      detail: error.localizedDescription, listID: list.id))
                explanation.append("The filter is not used because it cannot be read, so every published item is listed.")
            }
        }
        let matching = items.count
        if let fieldID = list.sortFieldID {
            if let field = collection.field(fieldID), sortableTypes.contains(field.type) {
                items = sorted(items, by: fieldID, direction: list.sortDirection)
                explanation.append("Ordered by \(field.key), \(list.sortDirection.title.lowercased()); items without a value come last and ties keep the Items order.")
            } else {
                findings.append(.init(kind: .listSortField, collectionID: collection.id, nodeID: list.repeatedNodeID, listID: list.id))
                explanation.append("The order field is missing or cannot be ordered, so items keep the Items order.")
            }
        } else {
            explanation.append("Items keep the order of the Items list.")
        }
        if let limit = list.limit, items.count > limit {
            items = Array(items.prefix(limit))
            explanation.append("The limit keeps the first \(limit).")
        }
        let size = min(max(1, list.pageSize), CollectionList.maximumPageSize)
        let pages = max(1, (items.count + size - 1) / size)
        explanation.append("\(size) per page: \(pages) written \(pages == 1 ? "page" : "pages").")
        return CollectionListResolution(publishedCount: published.count, matchingCount: matching, items: items,
                                        pageSize: size, explanation: explanation)
    }

    private static func sorted(_ items: [CollectionItem], by field: CollectionFieldID,
                               direction: CollectionListSortDirection) -> [CollectionItem] {
        var present: [(offset: Int, item: CollectionItem, value: CollectionFieldValue)] = []
        var missing: [CollectionItem] = []
        for (offset, item) in items.enumerated() {
            if let value = item.value(for: field), !value.isEmpty {
                present.append((offset: offset, item: item, value: value))
            } else {
                missing.append(item)
            }
        }
        present.sort { a, b in
            let order = compare(a.value, b.value)
            guard order != .orderedSame else { return a.offset < b.offset }
            return direction == .ascending ? order == .orderedAscending : order == .orderedDescending
        }
        return present.map { $0.item } + missing
    }

    /// Numbers and dates by value; text ignoring case and accents, with
    /// digits compared as numbers, the same on every Mac.
    private static func compare(_ a: CollectionFieldValue, _ b: CollectionFieldValue) -> ComparisonResult {
        switch (a, b) {
        case (.number(let x), .number(let y)):
            return x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
        case (.date(let x), .date(let y)):
            return x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
        case (.text(let x), .text(let y)):
            return x.compare(y, options: [.caseInsensitive, .diacriticInsensitive, .numeric], range: nil,
                             locale: Locale(identifier: "en_US_POSIX"))
        default:
            return .orderedSame
        }
    }

    /// Every usable list by the page it is on. `pages` are the pages being
    /// built (component-resolved) or the document's own. Unusable lists are
    /// reported and left out; their page is written as designed.
    fileprivate static func placements(_ document: CanonicalDocument, pages: [DocumentPage],
                                       findings: inout [CollectionTemplateFinding]) -> [PageID: [Placement]] {
        let pagesByID = Dictionary(pages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let templatePages = CollectionTemplates.templatePageIDs(document)
        var found: [CollectionTemplateFinding] = []
        var result: [PageID: [Placement]] = [:]
        for collection in document.collections {
            let linksAvailable = CollectionTemplates.activePage(for: collection, in: document) != nil
            let schema = collection.expressionSchema(in: document.collections)
            for list in collection.lists {
                func report(_ kind: CollectionTemplateFinding.Kind, node: NodeID? = nil) {
                    found.append(.init(kind: kind, collectionID: collection.id, nodeID: node ?? list.repeatedNodeID, listID: list.id))
                }
                guard let authored = document.pages.first(where: { $0.id == list.pageID }) else { report(.missingPage); continue }
                guard authored.role == .home || authored.role == .standard, !templatePages.contains(authored.id) else {
                    report(.listPage); continue
                }
                let page = pagesByID[authored.id] ?? authored
                let nodes = Dictionary(page.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                guard let repeated = nodes[list.repeatedNodeID] else { report(.listLayerMissing); continue }
                guard case .node(let parentID) = repeated.parent, let parent = nodes[parentID],
                      parent.kind == .stack || parent.kind == .grid else { report(.listNeedsFlow); continue }
                let layers = Self.subtree(repeated.id, in: page)
                let others = result[page.id] ?? []
                guard !others.contains(where: { $0.subtree.contains(repeated.id) || layers.contains($0.list.repeatedNodeID) }) else {
                    report(.listOverlap); continue
                }
                func control(_ id: NodeID?) -> NodeID? {
                    guard let id else { return nil }
                    guard let node = nodes[id], node.kind.isLinkControl, !layers.contains(id),
                          !others.contains(where: { $0.subtree.contains(id) }) else {
                        report(.paginationControl, node: id)
                        return nil
                    }
                    return id
                }
                var compiled = CollectionTemplates.Compiled()
                CollectionTemplates.compileBindings(list.bindings, into: &compiled, collection: collection,
                                                    nodes: page.nodes.filter { layers.contains($0.id) }, schema: schema,
                                                    linksAvailable: linksAvailable, listID: list.id, findings: &found)
                let resolution = resolve(list, collection: collection, collections: document.collections, findings: &found)
                result[page.id, default: []].append(Placement(collection: collection, list: list, subtree: layers,
                    compiled: compiled, resolution: resolution,
                    previousNodeID: control(list.previousNodeID), nextNodeID: control(list.nextNodeID)))
            }
        }
        findings += found
        return result
    }

    /// SF-1003-002/006: written page `number` of `page`: each list's layer is
    /// repeated once per item on that page (not at all past its last page)
    /// and bound to the item; Previous and Next open the neighbouring pages
    /// or are left out. Interactions and section links inside a copy follow
    /// the copy.
    fileprivate static func expand(_ page: DocumentPage, placements: [Placement], number: Int,
                                   document: CanonicalDocument) -> DocumentPage {
        let assets = Set(document.imageAssets.map(\.id))
        var copies: [NodeID: [DocumentNode]] = [:], roots: [NodeID: [NodeID]] = [:]
        var repeated = Set<NodeID>(), removed = Set<NodeID>()
        var controls: [NodeID: CanonicalLinkTarget] = [:]
        for placement in placements {
            let root = placement.list.repeatedNodeID
            repeated.formUnion(placement.subtree)
            let items = placement.resolution.items(onPage: number)
            let originals = page.nodes.filter { placement.subtree.contains($0.id) }
            var written: [DocumentNode] = []
            for (slot, item) in items.enumerated() {
                let ids = Dictionary(uniqueKeysWithValues: placement.subtree.map { ($0, copyID($0, slot: slot)) })
                let context = placement.collection.expressionContext(for: item, in: document.collections)
                for original in originals {
                    var copy = DocumentNode(id: ids[original.id] ?? original.id, kind: original.kind, name: original.name,
                                            parent: original.parent, childIDs: original.childIDs.map { ids[$0] ?? $0 },
                                            properties: original.properties)
                    if original.id != root, case .node(let parentID) = original.parent { copy.parent = .node(ids[parentID] ?? parentID) }
                    if slot > 0 {
                        for index in copy.properties.indices {
                            let key = copy.properties[index].key.rawValue
                            if key == CanonicalEventGraph.interactionsKey {
                                copy.properties[index].value = CanonicalEventGraph.remappingTargets(copy.properties[index].value,
                                                                                                    nodeMap: ids, freshIdentity: false)
                            } else if key == CanonicalLinkTarget.namespace + "nodeID", case .string(let old) = copy.properties[index].value,
                                      let oldID = NodeID(uuidString: old), let mapped = ids[oldID] {
                                copy.properties[index].value = .string(mapped.description)
                            }
                        }
                    }
                    CollectionTemplates.bind(&copy, source: original.id, compiled: placement.compiled,
                                             collection: placement.collection, item: item, context: context, assets: assets)
                    written.append(copy)
                }
            }
            copies[root] = written
            roots[root] = items.indices.map { copyID(root, slot: $0) }
            if let previous = placement.previousNodeID {
                if number > 1 { controls[previous] = .page(pageLinkID(page.id, number: number - 1)) } else { removed.insert(previous) }
            }
            if let next = placement.nextNodeID {
                if number < placement.resolution.pageCount {
                    controls[next] = .page(pageLinkID(page.id, number: number + 1))
                } else {
                    removed.insert(next)
                }
            }
        }
        var nodes: [DocumentNode] = []
        for node in page.nodes where !removed.contains(node.id) {
            if let written = copies[node.id] { nodes += written; continue }
            guard !repeated.contains(node.id) else { continue }
            var copy = node
            copy.childIDs = node.childIDs.flatMap { roots[$0] ?? [$0] }.filter { !removed.contains($0) }
            if let target = controls[node.id] { CollectionTemplates.setLink(target, on: &copy) }
            nodes.append(copy)
        }
        var result = page
        result.nodes = nodes
        result.rootNodeIDs = page.rootNodeIDs.filter { !removed.contains($0) }
        result.route = pageRoute(page.route, number: number)
        if number > 1 { result.name = page.name + ", page \(number)" }
        return result
    }

    fileprivate static func outputPages(_ page: DocumentPage, placements: [Placement],
                                        document: CanonicalDocument) -> [CollectionTemplates.OutputPage] {
        let count = placements.map(\.resolution.pageCount).max() ?? 1
        return (1...count).map { number in
            CollectionTemplates.OutputPage(page: expand(page, placements: placements, number: number, document: document),
                                           isPrimary: number == 1, itemID: nil, listPageNumber: number)
        }
    }

    /// The pages styles are written from: a page with lists contributes its
    /// first written page, which holds every copy any later page uses.
    static func stylePages(_ pages: [DocumentPage], document: CanonicalDocument) -> [DocumentPage] {
        var ignored: [CollectionTemplateFinding] = []
        let listed = placements(document, pages: pages, findings: &ignored)
        guard !listed.isEmpty else { return pages }
        return pages.map { page in listed[page.id].map { expand(page, placements: $0, number: 1, document: document) } ?? page }
    }

    /// Link identities that are not document pages, with their addresses:
    /// every item page (for layers that open the item's page) and every list
    /// page after the first (for Previous and Next).
    static func linkRoutes(_ document: CanonicalDocument, pages: [DocumentPage]) -> [PageID: PageRoute] {
        var result = CollectionTemplates.itemLinkRoutes(document)
        var ignored: [CollectionTemplateFinding] = []
        for (pageID, placements) in placements(document, pages: pages, findings: &ignored) {
            guard let page = pages.first(where: { $0.id == pageID }) ?? document.pages.first(where: { $0.id == pageID }) else { continue }
            let count = placements.map(\.resolution.pageCount).max() ?? 1
            for number in stride(from: 2, through: count, by: 1) {
                result[pageLinkID(pageID, number: number)] = pageRoute(page.route, number: number)
            }
        }
        return result
    }

    /// SF-1003-004: everything that keeps a list, or part of it, from being
    /// written as designed, including later pages whose address is taken.
    static func findings(_ document: CanonicalDocument) -> [CollectionTemplateFinding] {
        var result: [CollectionTemplateFinding] = []
        let listed = placements(document, pages: document.pages, findings: &result)
        let templatePages = CollectionTemplates.templatePageIDs(document)
        var taken = Set(document.pages.filter { $0.role != .componentDefinition && !templatePages.contains($0.id) }.map(\.route.rawValue))
        taken.formUnion(CollectionTemplates.itemLinkRoutes(document).values.map(\.rawValue))
        for page in document.pages {
            guard let placements = listed[page.id], let first = placements.first else { continue }
            let count = placements.map(\.resolution.pageCount).max() ?? 1
            for number in stride(from: 2, through: count, by: 1) where taken.contains(pageRoute(page.route, number: number).rawValue) {
                result.append(.init(kind: .routeCollision, collectionID: first.collection.id, nodeID: first.list.repeatedNodeID,
                                    listID: first.list.id))
                break
            }
        }
        return result
    }

    /// SF-1003-008: sanitized record of one list operation.
    static func diagnostic(_ operation: String, document: CanonicalDocument, startedAt start: Date) -> CollectionEditDiagnostic {
        let found = findings(document)
        var ignored: [CollectionTemplateFinding] = []
        let listed = placements(document, pages: document.pages, findings: &ignored)
        return CollectionEditDiagnostic(requirementID: requirementID, operation: operation,
            collectionIdentifiers: document.collections.filter { !$0.lists.isEmpty }.map(\.id.description).sorted(),
            itemCount: listed.values.joined().reduce(0) { $0 + $1.resolution.items.count },
            durationMilliseconds: max(0, Int(Date().timeIntervalSince(start) * 1_000)),
            failureCategory: found.first?.kind.rawValue ?? "none")
    }
}

/// SF-1003-002: template editing in the Collections editor draft.
extension CollectionEditing {
    /// Layers a template can bind: Text and Image layers in canvas order.
    static func bindableNodes(_ page: DocumentPage) -> [DocumentNode] {
        page.canonicalDepthFirstNodes().filter { $0.kind == .text || $0.kind == .image }
    }

    /// Choosing another page clears bindings (they belong to the old page's
    /// layers) and keeps the title expression; nil removes the template.
    static func setTemplatePage(_ pageID: PageID?, in collection: inout ContentCollection) {
        guard let pageID else { collection.template = nil; return }
        guard collection.template?.pageID != pageID else { return }
        collection.template = CollectionTemplate(pageID: pageID, title: collection.template?.title)
    }

    /// Empty text removes the binding. Returns false, changing nothing, when
    /// the text is not a syntactically valid expression.
    @discardableResult
    static func setTitle(_ source: String, in collection: inout ContentCollection) -> Bool {
        guard collection.template != nil else { return false }
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { collection.template?.title = nil; return true }
        guard let expression = SiteExpression(source: source) else { return false }
        collection.template?.title = expression
        return true
    }

    @discardableResult
    static func setTextBinding(_ source: String, node: NodeID, in collection: inout ContentCollection) -> Bool {
        guard collection.template != nil else { return false }
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            replaceBinding(nil, node: node, target: .text, in: &collection)
            return true
        }
        guard let expression = SiteExpression(source: source) else { return false }
        replaceBinding(.text(node, expression), node: node, target: .text, in: &collection)
        return true
    }

    static func setImageBinding(_ field: CollectionFieldID?, node: NodeID, in collection: inout ContentCollection) {
        guard collection.template != nil else { return }
        replaceBinding(field.map { .image(node, field: $0) }, node: node, target: .image, in: &collection)
    }

    private static func replaceBinding(_ binding: CollectionBinding?, node: NodeID, target: CollectionBindingTarget,
                                       in collection: inout ContentCollection) {
        guard var template = collection.template else { return }
        template.bindings.removeAll { $0.nodeID == node && $0.target == target }
        if let binding { template.bindings.append(binding) }
        template.bindings.sort { ($0.nodeID.description, $0.target.rawValue) < ($1.nodeID.description, $1.target.rawValue) }
        collection.template = template
    }

    /// The expression's result for the first published item (or first item),
    /// or why it cannot be used. For the editor's live preview only.
    static func templatePreview(_ source: String, collection: ContentCollection,
                                collections: [ContentCollection]) -> (text: String?, error: String?) {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return (nil, nil) }
        do {
            let program = try SiteExpressionEngine.check(source, schema: collection.expressionSchema(in: collections))
            guard let item = CollectionTemplates.publishedItems(collection).first ?? collection.items.first else { return (nil, nil) }
            let value = SiteExpressionEngine.evaluate(program, context: collection.expressionContext(for: item, in: collections)).value
            return (value.renderedText, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    /// SF-1004-003: which rules won for the previewed item, in evaluation
    /// order, then runtime findings; each line once. Empty when the
    /// expression is empty or unusable (`templatePreview` gives the error).
    static func templatePreviewExplanation(_ source: String, collection: ContentCollection,
                                           collections: [ContentCollection]) -> [String] {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let program = try? SiteExpressionEngine.check(source, schema: collection.expressionSchema(in: collections)),
              let item = CollectionTemplates.publishedItems(collection).first ?? collection.items.first else { return [] }
        let evaluation = SiteExpressionEngine.evaluate(program, context: collection.expressionContext(for: item, in: collections))
        var lines: [String] = []
        for line in evaluation.decisions.map(\.explanation) + evaluation.findings.map(\.message) where !lines.contains(line) {
            lines.append(line)
        }
        return lines
    }

    /// SF-1004-006: where an unusable expression goes wrong, for the editor to
    /// mark: the error's range in Unicode scalars, clamped to the text (one
    /// character at least, or the empty range at the end), the place in words
    /// for VoiceOver, and the error's recovery suggestion. Nil when the
    /// expression is empty or usable.
    static func templatePreviewProblem(_ source: String, collection: ContentCollection,
                                       collections: [ContentCollection]) -> (range: Range<Int>, place: String, suggestion: String?)? {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let problem: SiteExpressionError
        do {
            _ = try SiteExpressionEngine.check(source, schema: collection.expressionSchema(in: collections))
            return nil
        } catch let found as SiteExpressionError {
            problem = found
        } catch {
            return nil
        }
        let length = source.unicodeScalars.count
        let start = min(max(0, problem.range.start), length)
        let end = start == length ? length : min(max(start + 1, problem.range.end), length)
        let place = start == length ? "at the end" : (end - start == 1 ? "at character \(start + 1)" : "at characters \(start + 1) to \(end)")
        return (start..<end, place, problem.recoverySuggestion)
    }
}

/// SF-1003-002: list editing in the Collections editor draft.
extension CollectionEditing {
    /// Layers a list can repeat: layers directly inside a Stack or Grid, in canvas order.
    static func repeatableNodes(_ page: DocumentPage) -> [DocumentNode] {
        let containers = Set(page.nodes.filter { $0.kind == .stack || $0.kind == .grid }.map(\.id))
        return page.canonicalDepthFirstNodes().filter { node in
            if case .node(let parent) = node.parent { return containers.contains(parent) }
            return false
        }
    }

    /// Layers inside a repeated layer that a list can fill: Text, Image, Link
    /// and Button, in canvas order.
    static func listBindableNodes(_ page: DocumentPage, repeating node: NodeID) -> [DocumentNode] {
        let layers = CollectionLists.subtree(node, in: page)
        return page.canonicalDepthFirstNodes().filter {
            layers.contains($0.id) && ($0.kind == .text || $0.kind == .image || $0.kind.isLinkControl)
        }
    }

    /// Link and Button layers outside the repeated layer, for Previous and Next.
    static func paginationNodes(_ page: DocumentPage, repeating node: NodeID) -> [DocumentNode] {
        let layers = CollectionLists.subtree(node, in: page)
        return page.canonicalDepthFirstNodes().filter { $0.kind.isLinkControl && !layers.contains($0.id) }
    }

    /// A list on `page` that repeats `node`, in Items order, 12 per page.
    /// False, changing nothing, when this collection already repeats the
    /// layer or has the most lists.
    @discardableResult
    static func addList(page: PageID, repeating node: NodeID, to collection: inout ContentCollection) -> Bool {
        guard collection.lists.count < CollectionList.maximumListsPerCollection,
              !collection.lists.contains(where: { $0.repeatedNodeID == node }) else { return false }
        collection.lists.append(CollectionList(pageID: page, repeatedNodeID: node))
        return true
    }

    static func removeList(_ list: NodeID, from collection: inout ContentCollection) {
        collection.lists.removeAll { $0.repeatedNodeID == list }
    }

    static func updateList(_ list: NodeID, in collection: inout ContentCollection, _ change: (inout CollectionList) -> Void) {
        guard let index = collection.lists.firstIndex(where: { $0.repeatedNodeID == list }) else { return }
        change(&collection.lists[index])
    }

    /// Empty text removes the filter. False, changing nothing, for an unknown
    /// list or text that is not a syntactically valid expression.
    @discardableResult
    static func setListFilter(_ source: String, list: NodeID, in collection: inout ContentCollection) -> Bool {
        guard collection.lists.contains(where: { $0.repeatedNodeID == list }) else { return false }
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updateList(list, in: &collection) { $0.filter = nil }
            return true
        }
        guard let expression = SiteExpression(source: source) else { return false }
        updateList(list, in: &collection) { $0.filter = expression }
        return true
    }

    @discardableResult
    static func setListTextBinding(_ source: String, node: NodeID, list: NodeID, in collection: inout ContentCollection) -> Bool {
        guard collection.lists.contains(where: { $0.repeatedNodeID == list }) else { return false }
        let binding: CollectionBinding?
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            binding = nil
        } else {
            guard let expression = SiteExpression(source: source) else { return false }
            binding = .text(node, expression)
        }
        updateList(list, in: &collection) { $0.bindings = replacingBinding(binding, node: node, target: .text, in: $0.bindings) }
        return true
    }

    static func setListImageBinding(_ field: CollectionFieldID?, node: NodeID, list: NodeID, in collection: inout ContentCollection) {
        let binding: CollectionBinding? = field.map { CollectionBinding.image(node, field: $0) }
        updateList(list, in: &collection) { $0.bindings = replacingBinding(binding, node: node, target: .image, in: $0.bindings) }
    }

    /// A Link or Button layer that opens each item's page, or keeps its own link.
    static func setListLinkBinding(_ opensItem: Bool, node: NodeID, list: NodeID, in collection: inout ContentCollection) {
        let binding: CollectionBinding? = opensItem ? CollectionBinding.link(node) : nil
        updateList(list, in: &collection) { $0.bindings = replacingBinding(binding, node: node, target: .link, in: $0.bindings) }
    }

    /// One binding per layer and target, sorted by layer identity, then target.
    static func replacingBinding(_ binding: CollectionBinding?, node: NodeID, target: CollectionBindingTarget,
                                 in bindings: [CollectionBinding]) -> [CollectionBinding] {
        var result = bindings.filter { !($0.nodeID == node && $0.target == target) }
        if let binding { result.append(binding) }
        return result.sorted { ($0.nodeID.description, $0.target.rawValue) < ($1.nodeID.description, $1.target.rawValue) }
    }

    /// What the list would show now, and why. For the editor's live preview.
    static func listPreview(_ list: CollectionList, collection: ContentCollection,
                            collections: [ContentCollection]) -> CollectionListResolution {
        var ignored: [CollectionTemplateFinding] = []
        return CollectionLists.resolve(list, collection: collection, collections: collections, findings: &ignored)
    }
}

/// SF-1005 (OD-037, ADR-0073): the file formats a collection can import.
enum CollectionImportFormat: String, CaseIterable, Sendable {
    case csv, json

    /// The format a file name extension names, ignoring case; nil for any other file.
    init?(fileExtension: String) {
        self.init(rawValue: fileExtension.lowercased())
    }
}

/// SF-1005-001/004: why a file cannot be read. Nothing changes; messages name
/// rows, lines and rules, never file contents.
enum CollectionImportError: Error, Equatable, LocalizedError {
    case tooLarge, notText, empty, header, ragged(row: Int), unclosedQuote(line: Int), strayQuote(line: Int)
    case json, tooManyRows, tooManyColumns, duplicateMapping, unknownMapping
    /// The Import tab (ADR-0074): the chosen file cannot be read, is not CSV or
    /// JSON, or the preview no longer matches the draft it would replace.
    case unreadable, unsupportedFormat, stale

    var category: String {
        switch self {
        case .tooLarge: "too-large"
        case .notText: "not-text"
        case .empty: "empty"
        case .header: "header"
        case .ragged: "ragged"
        case .unclosedQuote: "unclosed-quote"
        case .strayQuote: "stray-quote"
        case .json: "json"
        case .tooManyRows: "too-many-rows"
        case .tooManyColumns: "too-many-columns"
        case .duplicateMapping: "duplicate-mapping"
        case .unknownMapping: "unknown-mapping"
        case .unreadable: "unreadable"
        case .unsupportedFormat: "unsupported-format"
        case .stale: "stale"
        }
    }

    var errorDescription: String? {
        switch self {
        case .tooLarge: "The file is larger than 5 MB. Split it into smaller files. Nothing changed."
        case .notText: "The file is not UTF-8 text. Save it as UTF-8 CSV or JSON. Nothing changed."
        case .empty: "The file has no rows to import. Nothing changed."
        case .header: "The first row must name every column once, without empty names. Nothing changed."
        case .ragged(let row): "Row \(row) has a different number of cells than the header row. Nothing changed."
        case .unclosedQuote(let line): "A quoted cell that starts on line \(line) never ends. Nothing changed."
        case .strayQuote(let line): "Line \(line) has a quote inside a cell that is not quoted, or text after a closing quote. Nothing changed."
        case .json: "The file must be a JSON array of objects whose values are text, numbers, true, false or null. Nothing changed."
        case .tooManyRows: "The file has more than \(ContentCollection.maximumItems) rows. Nothing changed."
        case .tooManyColumns: "The file has more than \(CollectionImportTable.maximumColumns) columns. Nothing changed."
        case .duplicateMapping: "Two columns fill the same field. Choose Skip for one of them."
        case .unknownMapping: "A column is matched to a field or position that no longer exists. Choose the columns again."
        case .unreadable: "The file could not be read. Check that it is available and try again. Nothing changed."
        case .unsupportedFormat: "Choose a file whose name ends in .csv or .json. Nothing changed."
        case .stale: "The collection changed after this preview was made. Check the new preview, then add it again."
        }
    }
}

/// SF-1005-001: a file read into rows of text cells. A nil cell is absent (a
/// JSON key that is missing or null) and keeps an item's value on update;
/// an empty cell clears it.
struct CollectionImportTable: Equatable, Sendable {
    static let maximumBytes = 5_000_000
    static let maximumColumns = 128
    let columns: [String]
    let rows: [[String?]]

    /// The first non-empty cell of `column` in the first rows, on one line and
    /// shortened, so the editor can show what a column holds next to its picker.
    func example(column: Int, rowsChecked: Int = 5, maximumCharacters: Int = 60) -> String? {
        for row in rows.prefix(rowsChecked) {
            guard column >= 0, column < row.count, let cell = row[column] else { continue }
            let line = (cell.split(whereSeparator: \.isNewline).first.map { String($0) } ?? "").trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            return line.count > maximumCharacters ? String(line.prefix(maximumCharacters - 1)) + "\u{2026}" : line
        }
        return nil
    }
}

/// SF-1005-002: what one column fills, as chosen in the editor's Import tab.
enum CollectionImportColumnTarget: Hashable, Sendable {
    case skip, address, field(CollectionFieldID)
}

/// SF-1005-002: how columns become fields. Built from the header
/// (`CollectionImport.suggestedMapping`) and changed in the editor; never stored.
struct CollectionImportMapping: Equatable, Sendable {
    /// Column position → the field it fills; other columns are skipped.
    var fields: [Int: CollectionFieldID] = [:]
    /// The column with item addresses; nil makes addresses from each row's title.
    var slugColumn: Int?
    /// New items start as drafts by default, so imported content is reviewed before it is published.
    var newItemStatus: CollectionItemStatus = .draft
    /// A row whose address matches an existing item updates it instead of adding one.
    var updatesMatchingItems = true

    func target(ofColumn column: Int) -> CollectionImportColumnTarget {
        if slugColumn == column { return .address }
        return fields[column].map { CollectionImportColumnTarget.field($0) } ?? .skip
    }

    /// Chooses what `column` fills. A field or the address moves from any
    /// other column, so a mapping chosen in the editor never fills a field twice.
    mutating func assign(_ target: CollectionImportColumnTarget, toColumn column: Int) {
        fields[column] = nil
        if slugColumn == column { slugColumn = nil }
        switch target {
        case .skip:
            break
        case .address:
            slugColumn = column
        case .field(let id):
            for (other, field) in fields where field == id { fields[other] = nil }
            fields[column] = id
        }
    }
}

/// SF-1005-004: one row that is not imported, located by row (1 is the first
/// data row) and column position (0-based; messages show it 1-based). Never
/// carries the cell's value.
struct CollectionImportProblem: Hashable, Sendable {
    enum Kind: String, Sendable {
        case text, number, date, image, reference, slug, duplicateSlug, requiredMissing, tooManyItems
    }

    let kind: Kind
    let row: Int
    var column: Int?

    var message: String {
        let place = "Row \(row)" + (column.map { ", column \($0 + 1)" } ?? "")
        switch kind {
        case .text: return place + ": the text is longer than 64 KB or contains a NUL character. The row is skipped."
        case .number: return place + ": not a number (use digits, an optional minus sign and a decimal point). The row is skipped."
        case .date: return place + ": not a date (use YYYY-MM-DD). The row is skipped."
        case .image: return place + ": no project image has this file name. Add the image first. The row is skipped."
        case .reference: return place + ": no item of the referenced collection has this address. The row is skipped."
        case .slug: return place + ": the address must use lowercase letters, digits and single hyphens (at most 64). The row is skipped."
        case .duplicateSlug: return place + ": an earlier row already uses this address. The row is skipped."
        case .requiredMissing: return place + ": the update would leave a required field of a published item empty. The row is skipped."
        case .tooManyItems: return place + ": the collection already has \(ContentCollection.maximumItems) items. The row is skipped."
        }
    }
}

/// SF-1005-002/003: what an import would do. `collection` is the result;
/// nothing is committed until the editor's Apply.
struct CollectionImportPreview: Equatable, Sendable {
    /// Problems listed per preview; `skipped` still counts every skipped row.
    static let maximumProblems = 1_000
    let collection: ContentCollection
    let added: Int
    let updated: Int
    let skipped: Int
    /// New items kept as drafts although Published was chosen, because a required field is empty.
    let keptAsDraft: Int
    let problems: [CollectionImportProblem]

    var summary: String {
        var parts = ["Adds \(added) \(added == 1 ? "item" : "items")", "updates \(updated)", "skips \(skipped) \(skipped == 1 ? "row" : "rows")"]
        if keptAsDraft > 0 { parts.append("keeps \(keptAsDraft) new \(keptAsDraft == 1 ? "item" : "items") as drafts because a required field is empty") }
        return parts.joined(separator: ", ") + "."
    }
}

/// SF-1005 (OD-037, ADR-0073): local CSV and JSON files into a collection.
/// Pure: reading, matching and previewing never change the document; the
/// Collections editor puts the result in its draft and Apply commits it as
/// one undoable change. No data source, path or credential is stored.
enum CollectionImport {
    static let requirementID = "SF-1005-002"

    /// The engine's only file access (ADR-0074): reads the one file the user
    /// chose, refusing a file over the size limit before reading it. Blocking;
    /// the editor calls it off the main actor. The path is never stored.
    static func read(_ url: URL) throws -> CollectionImportTable {
        guard let format = CollectionImportFormat(fileExtension: url.pathExtension) else {
            throw CollectionImportError.unsupportedFormat
        }
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { throw CollectionImportError.unreadable }
        guard (values.fileSize ?? 0) <= CollectionImportTable.maximumBytes else { throw CollectionImportError.tooLarge }
        guard let data = try? Data(contentsOf: url) else { throw CollectionImportError.unreadable }
        return try parse(data, format: format)
    }

    /// A number as typed or exported: ASCII digits, sign, point and exponent
    /// only (no "inf", "nan", hex or grouping), and finite. Import and the
    /// editor's number fields share it, so both accept what `numberText` writes.
    static func parseNumber(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || $0 == 43 || $0 == 45 || $0 == 46 || $0 == 69 || $0 == 101 }),
              let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }

    /// "Add to Draft": the editor draft with `base` replaced by the preview's
    /// result. Refused as stale when the draft no longer holds `base` exactly,
    /// so an import never overwrites edits made after its preview.
    static func merge(_ preview: CollectionImportPreview, base: ContentCollection,
                      into draft: [ContentCollection]) throws -> [ContentCollection] {
        guard preview.collection.id == base.id, let index = draft.firstIndex(where: { $0.id == base.id }),
              draft[index] == base else { throw CollectionImportError.stale }
        var result = draft
        result[index] = preview.collection
        return result
    }

    static func parse(_ data: Data, format: CollectionImportFormat) throws -> CollectionImportTable {
        guard data.count <= CollectionImportTable.maximumBytes else { throw CollectionImportError.tooLarge }
        switch format {
        case .csv:
            guard let text = String(data: data, encoding: .utf8) else { throw CollectionImportError.notText }
            return try parseCSV(text)
        case .json:
            // A UTF-8 byte order mark is ignored, as in CSV files.
            return try parseJSON(data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data)
        }
    }

    /// RFC 4180 CSV: comma separated, the first row names the columns,
    /// double quotes around cells with commas, quotes or line breaks, `""`
    /// for a quote; LF, CRLF or CR line ends (stored as LF inside a quoted
    /// cell); a leading byte order mark and blank lines are ignored. Every row
    /// must have as many cells as the header.
    static func parseCSV(_ text: String) throws -> CollectionImportTable {
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        var records: [[String]] = []
        var record: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false, line = 1, quoteLine = 1, index = 0
        func endField() { record.append(String(field)); field = String.UnicodeScalarView() }
        func endRecord() {
            endField()
            if !(record.count == 1 && record[0].isEmpty) { records.append(record) }
            record = []
        }
        while index < scalars.count {
            let scalar = scalars[index]
            if inQuotes {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                    if index + 1 < scalars.count, !["," as Unicode.Scalar, "\n", "\r"].contains(scalars[index + 1]) {
                        throw CollectionImportError.strayQuote(line: line)
                    }
                } else if scalar == "\r" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\n" { index += 1 }
                    field.append("\n")
                    line += 1
                } else {
                    if scalar == "\n" { line += 1 }
                    field.append(scalar)
                }
                index += 1
                continue
            }
            switch scalar {
            case "\"":
                guard field.isEmpty else { throw CollectionImportError.strayQuote(line: line) }
                inQuotes = true
                quoteLine = line
            case ",":
                endField()
            case "\r":
                if index + 1 < scalars.count, scalars[index + 1] == "\n" { index += 1 }
                endRecord()
                line += 1
            case "\n":
                endRecord()
                line += 1
            default:
                field.append(scalar)
            }
            index += 1
        }
        guard !inQuotes else { throw CollectionImportError.unclosedQuote(line: quoteLine) }
        if !field.isEmpty || !record.isEmpty { endRecord() }
        guard let header = records.first else { throw CollectionImportError.empty }
        let columns = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard columns.count <= CollectionImportTable.maximumColumns else { throw CollectionImportError.tooManyColumns }
        guard !columns.contains(where: \.isEmpty), Set(columns.map { $0.lowercased() }).count == columns.count else {
            throw CollectionImportError.header
        }
        let rows = Array(records.dropFirst())
        guard !rows.isEmpty else { throw CollectionImportError.empty }
        guard rows.count <= ContentCollection.maximumItems else { throw CollectionImportError.tooManyRows }
        for (offset, row) in rows.enumerated() where row.count != columns.count {
            throw CollectionImportError.ragged(row: offset + 1)
        }
        return CollectionImportTable(columns: columns, rows: rows.map { $0.map { Optional($0) } })
    }

    private enum JSONScalar: Decodable {
        case text(String), number(Double), boolean(Bool), null

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .boolean(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else if let value = try? container.decode(String.self) {
                self = .text(value)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Nested values cannot be imported.")
            }
        }

        var cell: String? {
            switch self {
            case .text(let value): value
            case .number(let value): SiteExpressionEngine.numberText(value)
            case .boolean(let value): value ? "true" : "false"
            case .null: nil
            }
        }
    }

    /// A JSON array of objects. Columns are every key used, sorted, so the
    /// result never depends on key order in the file.
    static func parseJSON(_ data: Data) throws -> CollectionImportTable {
        let objects: [[String: JSONScalar]]
        do { objects = try JSONDecoder().decode([[String: JSONScalar]].self, from: data) } catch {
            throw CollectionImportError.json
        }
        guard !objects.isEmpty else { throw CollectionImportError.empty }
        guard objects.count <= ContentCollection.maximumItems else { throw CollectionImportError.tooManyRows }
        let columns = Set(objects.flatMap(\.keys)).sorted()
        guard columns.count <= CollectionImportTable.maximumColumns else { throw CollectionImportError.tooManyColumns }
        guard !columns.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(columns.map { $0.lowercased() }).count == columns.count else { throw CollectionImportError.header }
        return CollectionImportTable(columns: columns, rows: objects.map { object in columns.map { object[$0]?.cell } })
    }

    private static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// A column named `slug` or `address` holds item addresses; another
    /// column fills the field whose name or label it matches, ignoring case,
    /// spaces and punctuation. Each field is filled by at most one column.
    static func suggestedMapping(_ table: CollectionImportTable, for collection: ContentCollection) -> CollectionImportMapping {
        var mapping = CollectionImportMapping()
        var used = Set<CollectionFieldID>()
        for (index, column) in table.columns.enumerated() {
            let name = normalized(column)
            if mapping.slugColumn == nil, name == "slug" || name == "address" {
                mapping.slugColumn = index
                continue
            }
            if let field = collection.fields.first(where: {
                !used.contains($0.id) && (normalized($0.key) == name || normalized($0.label) == name)
            }) {
                mapping.fields[index] = field.id
                used.insert(field.id)
            }
        }
        return mapping
    }

    private enum Converted {
        case value(CollectionFieldValue?)
        case problem(CollectionImportProblem.Kind)
    }

    /// Name lookups built once per preview, so a file of 10,000 rows stays
    /// linear instead of searching every asset and item for every cell.
    private struct Lookup {
        var assetsByName: [String: AssetID] = [:]
        var itemsBySlug: [CollectionID: [String: CollectionItemID]] = [:]

        init(collection: ContentCollection, collections: [ContentCollection], assets: [ImageAsset]) {
            // Earlier assets win, as a search in asset order would.
            for asset in assets {
                for name in [asset.originalFilename.lowercased(), asset.displayName.lowercased(), asset.id.description]
                    where assetsByName[name] == nil {
                    assetsByName[name] = asset.id
                }
            }
            for field in collection.fields where field.type == .reference {
                guard let targetID = field.referencedCollectionID, itemsBySlug[targetID] == nil,
                      let target = collections.first(where: { $0.id == targetID }) else { continue }
                var slugs: [String: CollectionItemID] = [:]
                for item in target.items where slugs[item.slug] == nil { slugs[item.slug] = item.id }
                itemsBySlug[targetID] = slugs
            }
        }
    }

    /// One cell as a field value: empty clears; text as written; numbers in
    /// plain or exponent form (as spreadsheets and JSON write them); dates as
    /// YYYY-MM-DD; images by project file name, display name or identity
    /// (ignoring case); references by the referenced item's address.
    private static func convert(_ cell: String, field: CollectionField, lookup: Lookup) -> Converted {
        let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .value(nil) }
        switch field.type {
        case .text, .richText:
            guard cell.utf8.count <= ContentCollection.maximumTextBytes, !cell.contains("\u{0}") else { return .problem(.text) }
            return .value(.text(cell))
        case .number:
            guard let number = parseNumber(trimmed) else { return .problem(.number) }
            return .value(.number(number))
        case .date:
            guard let date = SiteExpressionDate(iso: trimmed) else { return .problem(.date) }
            return .value(.date(date))
        case .image:
            guard let asset = lookup.assetsByName[trimmed.lowercased()] else { return .problem(.image) }
            return .value(.image(asset))
        case .reference:
            guard let targetID = field.referencedCollectionID,
                  let item = lookup.itemsBySlug[targetID]?[trimmed] else { return .problem(.reference) }
            return .value(.reference(item))
        }
    }

    private static func missesRequired(_ item: CollectionItem, in collection: ContentCollection) -> Bool {
        collection.fields.contains { $0.isRequired && (item.value(for: $0.id).map { $0.isEmpty } ?? true) }
    }

    static func validate(_ mapping: CollectionImportMapping, table: CollectionImportTable, collection: ContentCollection) throws {
        let targets = Array(mapping.fields.values)
        guard Set(targets).count == targets.count else { throw CollectionImportError.duplicateMapping }
        let positions = 0..<table.columns.count
        guard targets.allSatisfy({ collection.field($0) != nil }), mapping.fields.keys.allSatisfy({ positions.contains($0) }),
              mapping.slugColumn.map({ positions.contains($0) }) ?? true else { throw CollectionImportError.unknownMapping }
    }

    /// SF-1005-003: rows in file order. A row with any unusable cell or
    /// address is skipped whole and reported (the first
    /// `CollectionImportPreview.maximumProblems` problems are listed). With an
    /// address column, a row whose address matches an item updates it (absent
    /// cells keep a value, empty cells clear it, the status stays); every
    /// other row, including one whose address cell is empty, adds an item with
    /// the chosen status (a draft when a required field is empty), with its
    /// own address or one made from its title, made unique. An address is
    /// claimed only by a row that is used, so a skipped row never blocks a
    /// later one. References resolve against `collections` as passed in.
    static func preview(_ table: CollectionImportTable, mapping: CollectionImportMapping, into collection: ContentCollection,
                        collections: [ContentCollection], assets: [ImageAsset]) throws -> CollectionImportPreview {
        try validate(mapping, table: table, collection: collection)
        let lookup = Lookup(collection: collection, collections: collections, assets: assets)
        var result = collection
        var problems: [CollectionImportProblem] = []
        var added = 0, updated = 0, skipped = 0, keptAsDraft = 0
        var slugs = Set(collection.items.map(\.slug)), seenInFile = Set<String>()
        var indexBySlug: [String: Int] = [:]
        for (index, item) in collection.items.enumerated() where indexBySlug[item.slug] == nil { indexBySlug[item.slug] = index }
        // Next suffix to try per base address, so many rows with one title stay linear.
        var nextSuffix: [String: Int] = [:]
        func uniqueSlug(_ base: String) -> String {
            guard slugs.contains(base) else { return base }
            var suffix = nextSuffix[base] ?? 2
            while slugs.contains("\(base)-\(suffix)") { suffix += 1 }
            nextSuffix[base] = suffix + 1
            return "\(base)-\(suffix)"
        }
        func skip(_ rowProblems: [CollectionImportProblem]) {
            problems += rowProblems.prefix(max(0, CollectionImportPreview.maximumProblems - problems.count))
            skipped += 1
        }
        let columns = mapping.fields.sorted { $0.key < $1.key }
        for (offset, cells) in table.rows.enumerated() {
            let row = offset + 1
            var values: [(field: CollectionFieldID, value: CollectionFieldValue?)] = []
            var rowProblems: [CollectionImportProblem] = []
            for (column, fieldID) in columns {
                guard column < cells.count, let cell = cells[column], let field = collection.field(fieldID) else { continue }
                switch convert(cell, field: field, lookup: lookup) {
                case .value(let value): values.append((field: fieldID, value: value))
                case .problem(let kind): rowProblems.append(.init(kind: kind, row: row, column: column))
                }
            }
            var slug: String?
            if let column = mapping.slugColumn {
                let text = (column < cells.count ? cells[column] : nil)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !text.isEmpty {
                    if !CollectionSlug.isValid(text) {
                        rowProblems.append(.init(kind: .slug, row: row, column: column))
                    } else if seenInFile.contains(text) {
                        rowProblems.append(.init(kind: .duplicateSlug, row: row, column: column))
                    } else {
                        slug = text
                    }
                }
            }
            guard rowProblems.isEmpty else {
                skip(rowProblems)
                continue
            }
            if mapping.updatesMatchingItems, let slug, let index = indexBySlug[slug] {
                var item = result.items[index]
                for entry in values { item.setValue(entry.value, for: entry.field) }
                if item.status == .published, missesRequired(item, in: result) {
                    skip([.init(kind: .requiredMissing, row: row)])
                    continue
                }
                result.items[index] = item
                seenInFile.insert(slug)
                updated += 1
                continue
            }
            guard result.items.count < ContentCollection.maximumItems else {
                skip([.init(kind: .tooManyItems, row: row)])
                continue
            }
            var item = CollectionItem(slug: "item", status: mapping.newItemStatus)
            for entry in values { item.setValue(entry.value, for: entry.field) }
            let unique = uniqueSlug(slug ?? CollectionSlug.make(from: CollectionEditing.displayTitle(item, in: result), fallback: "item"))
            guard CollectionSlug.isValid(unique) else {
                skip([.init(kind: .slug, row: row, column: mapping.slugColumn)])
                continue
            }
            item.slug = unique
            slugs.insert(unique)
            // The address this row got is claimed too, so a later row naming it
            // is a duplicate instead of updating an item this import just added.
            if let slug { seenInFile.insert(slug) }
            seenInFile.insert(unique)
            indexBySlug[unique] = result.items.count
            if item.status == .published, missesRequired(item, in: result) {
                item.status = .draft
                keptAsDraft += 1
            }
            result.items.append(item)
            added += 1
        }
        return CollectionImportPreview(collection: result, added: added, updated: updated, skipped: skipped,
                                       keptAsDraft: keptAsDraft, problems: problems)
    }

    /// SF-1005-008: sanitized record of one import: identities and counts only.
    static func diagnostic(_ operation: String, collection: CollectionID, preview: CollectionImportPreview?,
                           error: CollectionImportError?, startedAt start: Date) -> CollectionEditDiagnostic {
        CollectionEditDiagnostic(requirementID: error == nil ? requirementID : "SF-1005-004", operation: operation,
            collectionIdentifiers: [collection.description],
            itemCount: (preview?.added ?? 0) + (preview?.updated ?? 0),
            durationMilliseconds: max(0, Int(Date().timeIntervalSince(start) * 1_000)),
            failureCategory: error?.category ?? preview?.problems.first?.kind.rawValue ?? "none")
    }
}

/// SF-1002-008: sanitized record of one collection edit. Holds identities and
/// counts, never names or values.
struct CollectionEditDiagnostic: Equatable, Sendable {
    let requirementID: String
    let operation: String
    let collectionIdentifiers: [String]
    let itemCount: Int
    let durationMilliseconds: Int
    let failureCategory: String
}

enum CollectionEditError: Error, Equatable, LocalizedError {
    case busy, stale, revisionExhausted, unchanged
    case invalid([CollectionIssue])
    case refused(String)

    var category: String {
        switch self {
        case .busy: "busy"
        case .stale: "stale"
        case .revisionExhausted: "revision-exhausted"
        case .unchanged: "unchanged"
        case .invalid: "invalid"
        case .refused: "refused"
        }
    }

    var errorDescription: String? {
        switch self {
        case .busy: "Collections can't be changed while the project is busy. Nothing changed."
        case .stale: "The project changed after Collections opened. Nothing changed; cancel and open Collections again."
        case .revisionExhausted: "The document revision cannot accept another transaction. Nothing changed."
        case .unchanged: "Collections are unchanged."
        case .invalid(let issues): issues.first.map { "SF-1001-004: \($0.message)" } ?? "Collections are invalid."
        case .refused(let reason): reason
        }
    }
}

/// SF-1001-002 / SF-1002-002: pure draft operations used by the Collections
/// editor, automation and tests. Only `prepare` produces a command.
enum CollectionEditing {
    static func prepare(_ collections: [ContentCollection], openingRevision: UInt64, document: CanonicalDocument,
                        isLifecycleAvailable: Bool) throws -> DocumentCommand {
        guard isLifecycleAvailable else { throw CollectionEditError.busy }
        guard openingRevision == document.revision else { throw CollectionEditError.stale }
        guard document.revision < UInt64.max - 1 else { throw CollectionEditError.revisionExhausted }
        let issues = CanonicalCollections.issues(collections)
        guard issues.isEmpty else { throw CollectionEditError.invalid(issues) }
        guard collections != document.collections else { throw CollectionEditError.unchanged }
        var candidate = document
        candidate.collections = collections
        do {
            try candidate.validate()
        } catch {
            throw CollectionEditError.refused(error.localizedDescription)
        }
        return .setCollections(SetCollectionsCommand(documentID: document.id, collections: collections))
    }

    /// A new collection with a unique name and address and a required Title field.
    static func newCollection(in collections: [ContentCollection], name: String = "Untitled Collection") -> ContentCollection {
        let names = Set(collections.map { $0.name.lowercased() })
        var candidate = name
        var suffix = 2
        while names.contains(candidate.lowercased()) {
            candidate = "\(name) \(suffix)"
            suffix += 1
        }
        let slug = CollectionSlug.unique(CollectionSlug.make(from: candidate, fallback: "collection"),
                                         existing: Set(collections.map(\.slug)))
        let title = CollectionField(key: "title", label: "Title", type: .text, isRequired: true)
        return ContentCollection(name: candidate, slug: slug, fields: [title])
    }

    @discardableResult
    static func addField(label: String, type: CollectionFieldType, referencing target: CollectionID?,
                         to collection: inout ContentCollection) throws -> CollectionField {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard WebsiteMetadata.validText(trimmed, maximumBytes: 128) else {
            throw CollectionEditError.refused("Type a field label of at most 128 bytes.")
        }
        guard collection.fields.count < ContentCollection.maximumFields else {
            throw CollectionEditError.refused("A collection can have at most \(ContentCollection.maximumFields) fields.")
        }
        guard type != .reference || target != nil else {
            throw CollectionEditError.refused("Choose the collection this reference field points to.")
        }
        let key = CollectionField.suggestedKey(for: trimmed, existing: Set(collection.fields.map(\.key)))
        let field = CollectionField(key: key, label: trimmed, type: type,
                                    referencedCollectionID: type == .reference ? target : nil)
        collection.fields.append(field)
        return field
    }

    /// Removes the field and its values. The editor first shows how many
    /// items have a value (`CanonicalCollections.itemsWithValue`).
    static func removeField(_ field: CollectionFieldID, from collection: inout ContentCollection) {
        collection.fields.removeAll { $0.id == field }
        for index in collection.items.indices { collection.items[index].setValue(nil, for: field) }
    }

    /// Changing a type never discards data: text and rich text convert freely;
    /// any other change needs the field to be empty in every item.
    static func changeType(of field: CollectionFieldID, to type: CollectionFieldType, referencing target: CollectionID?,
                           in collection: inout ContentCollection) throws {
        guard let index = collection.fields.firstIndex(where: { $0.id == field }) else {
            throw CollectionEditError.refused("The field no longer exists.")
        }
        let current = collection.fields[index].type
        let textual: Set<CollectionFieldType> = [.text, .richText]
        guard (textual.contains(current) && textual.contains(type)) || CanonicalCollections.itemsWithValue(for: field, in: collection) == 0 else {
            throw CollectionEditError.refused("Items have values in this field. Clear them first, or add a new field of the other type.")
        }
        guard type != .reference || target != nil else {
            throw CollectionEditError.refused("Choose the collection this reference field points to.")
        }
        collection.fields[index].type = type
        collection.fields[index].referencedCollectionID = type == .reference ? target : nil
    }

    static func moveField(_ field: CollectionFieldID, by offset: Int, in collection: inout ContentCollection) {
        guard let index = collection.fields.firstIndex(where: { $0.id == field }) else { return }
        let destination = index + offset
        guard collection.fields.indices.contains(destination) else { return }
        collection.fields.swapAt(index, destination)
    }

    static func removeCollection(_ id: CollectionID, from collections: inout [ContentCollection]) throws {
        let referencing = CanonicalCollections.referencingFields(to: id, in: collections)
        guard referencing.isEmpty else {
            throw CollectionEditError.refused("Reference fields in other collections point here (\(referencing.map(\.label).joined(separator: ", "))). Remove or change them first.")
        }
        collections.removeAll { $0.id == id }
    }

    static func newItem(in collection: ContentCollection) -> CollectionItem {
        CollectionItem(slug: CollectionSlug.unique("item", existing: Set(collection.items.map(\.slug))))
    }

    /// Inserts a draft copy after the original and returns it.
    @discardableResult
    static func duplicate(_ item: CollectionItemID, in collection: inout ContentCollection) -> CollectionItem? {
        guard let index = collection.items.firstIndex(where: { $0.id == item }) else { return nil }
        let source = collection.items[index]
        let slug = CollectionSlug.unique(CollectionSlug.make(from: "\(source.slug.prefix(50)) copy"),
                                         existing: Set(collection.items.map(\.slug)))
        let copy = CollectionItem(slug: slug, status: .draft, values: source.values)
        collection.items.insert(copy, at: index + 1)
        return copy
    }

    static func missingRequiredFields(_ item: CollectionItem, in collection: ContentCollection) -> [CollectionField] {
        collection.fields.filter { field in
            field.isRequired && (item.value(for: field.id).map { $0.isEmpty } ?? true)
        }
    }

    /// Bulk action: publishes every draft that has all its required fields.
    /// Returns how many items changed.
    @discardableResult
    static func publishReadyDrafts(in collection: inout ContentCollection) -> Int {
        var count = 0
        for index in collection.items.indices where collection.items[index].status == .draft {
            guard missingRequiredFields(collection.items[index], in: collection).isEmpty else { continue }
            collection.items[index].status = .published
            count += 1
        }
        return count
    }

    /// SF-1002: status filter plus a case-insensitive search of the address
    /// and text values, in collection order.
    static func items(in collection: ContentCollection, matching query: String,
                      status: CollectionItemStatus?) -> [CollectionItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return collection.items.filter { item in
            guard status == nil || item.status == status else { return false }
            guard !needle.isEmpty else { return true }
            if item.slug.localizedCaseInsensitiveContains(needle) { return true }
            return item.values.contains { entry in
                if case .text(let text) = entry.value { return text.localizedCaseInsensitiveContains(needle) }
                return false
            }
        }
    }

    /// The first non-empty text field, else the address.
    static func displayTitle(_ item: CollectionItem, in collection: ContentCollection) -> String {
        for field in collection.fields where field.type == .text {
            if case .text(let text)? = item.value(for: field.id), !text.isEmpty { return text }
        }
        return item.slug
    }

    static func diagnostic(_ operation: String, collections: [ContentCollection], startedAt start: Date,
                           error: Error?) -> CollectionEditDiagnostic {
        let category = error.map { ($0 as? CollectionEditError)?.category ?? "command" } ?? "none"
        return CollectionEditDiagnostic(requirementID: error == nil ? "SF-1002-008" : "SF-1001-004", operation: operation,
                                        collectionIdentifiers: collections.map(\.id.description).sorted(),
                                        itemCount: collections.reduce(0) { $0 + $1.items.count },
                                        durationMilliseconds: max(0, Int(Date().timeIntervalSince(start) * 1_000)),
                                        failureCategory: category)
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
    // Schema 11 adds optional versioned image-asset organization metadata;
    // schema-ten assets migrate with organization omitted.
    // Schemas 12/13 add typed media/action bindings; schema 14 adds named
    // definition fallback slots without changing instance child ownership.
    // Schema 15 adds optional definition-owned property presentation metadata.
    // Historical schemas cannot acquire newer closed namespaces by permissive decoding.
    // Schema 21 adds decorative effects; schema 22 adds optional project-scoped
    // preferences (ADR-0027). A schema-21 project reopens unchanged.
    // Schema 23 adds linked border/corner/shadow values to reusable styles.
    // Schema 24 allows component instances inside definitions (OD-034).
    // Schema 25 adds instance-owned slot content, the empty slot state and
    // slot rules (OD-018).
    // Schema 26 adds property-only component variants and copies' variant
    // choices (OD-033, ADR-0029).
    // Schema 27 adds query containers and container-query rules (SF-0605,
    // ADR-0031), suppressed responsive-audit findings (SF-0606, ADR-0032) and
    // the site address and social image in website metadata (SF-1207, ADR-0034).
    static let currentSchemaVersion = CanonicalContainerQueries.documentSchema
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

    private struct SchemaEightEnvelope: Decodable {
        let schemaVersion: Int
        let document: SchemaEightDocument
        private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, document }
        init(from decoder: Decoder) throws {
            try requireExactKeys(CodingKeys.self, in: decoder)
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
            document = try values.decode(SchemaEightDocument.self, forKey: .document)
        }
    }

    private struct SchemaEightDocument: Decodable {
        let id: DocumentID
        let revision: UInt64
        let creationKind: ProjectCreationKind
        let templateID: TemplateID?
        let pages: [DocumentPage]
        let guides: [AuthoredGuide]
        let imageAssets: [ImageAsset]
        private enum CodingKeys: String, CodingKey, CaseIterable {
            case id, revision, creationKind, templateID, pages, guides, imageAssets
        }
        init(from decoder: Decoder) throws {
            try requireExactKeys(CodingKeys.self, in: decoder)
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(DocumentID.self, forKey: .id)
            revision = try values.decode(UInt64.self, forKey: .revision)
            creationKind = try values.decode(ProjectCreationKind.self, forKey: .creationKind)
            templateID = try values.decodeIfPresent(TemplateID.self, forKey: .templateID)
            pages = try values.decode([DocumentPage].self, forKey: .pages)
            guides = try values.decode([AuthoredGuide].self, forKey: .guides)
            imageAssets = try values.decode([ImageAsset].self, forKey: .imageAssets)
        }
        func migrated() -> CanonicalDocument {
            .init(id: id, revision: revision, creationKind: creationKind,
                  templateID: templateID, pages: pages, guides: guides,
                  imageAssets: imageAssets)
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
            try CanonicalComponentOverrides.validateSerializableRetention(document)
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

        var document: CanonicalDocument
        switch header.schemaVersion {
        case 1:
            do {
                let historicalDecoder = JSONDecoder()
                historicalDecoder.userInfo[SiteForgeDecodingPolicy.strictCurrentSchema] = true
                historicalDecoder.userInfo[SiteForgeDecodingPolicy.sourceDocumentSchema] = header.schemaVersion
                document = try historicalDecoder.decode(SchemaOneEnvelope.self, from: data).document.migrated()
            } catch {
                throw DocumentSerializationError.malformedInput
            }
        case 2:
            do {
                let historicalDecoder = JSONDecoder()
                historicalDecoder.userInfo[SiteForgeDecodingPolicy.strictCurrentSchema] = true
                historicalDecoder.userInfo[SiteForgeDecodingPolicy.sourceDocumentSchema] = header.schemaVersion
                document = try historicalDecoder.decode(SchemaTwoEnvelope.self, from: data).document.migrated()
            } catch {
                throw DocumentSerializationError.malformedInput
            }
        case 3:
            do {
                let historicalDecoder = JSONDecoder()
                historicalDecoder.userInfo[SiteForgeDecodingPolicy.strictCurrentSchema] = true
                historicalDecoder.userInfo[SiteForgeDecodingPolicy.sourceDocumentSchema] = header.schemaVersion
                document = try historicalDecoder.decode(SchemaThreeEnvelope.self, from: data).document.migrated()
            } catch {
                throw DocumentSerializationError.malformedInput
            }
        case 4:
            do {
                let historicalDecoder = JSONDecoder()
                historicalDecoder.userInfo[SiteForgeDecodingPolicy.strictCurrentSchema] = true
                historicalDecoder.userInfo[SiteForgeDecodingPolicy.sourceDocumentSchema] = header.schemaVersion
                document = try historicalDecoder.decode(SchemaFourEnvelope.self, from: data).document.migrated()
            } catch {
                throw DocumentSerializationError.malformedInput
            }
        case 5, 6, 7, 8:
            do {
                let strictDecoder = JSONDecoder()
                strictDecoder.userInfo[SiteForgeDecodingPolicy.strictCurrentSchema] = true
                strictDecoder.userInfo[SiteForgeDecodingPolicy.sourceDocumentSchema] = header.schemaVersion
                document = try strictDecoder.decode(SchemaEightEnvelope.self, from: data).document.migrated()
                if header.schemaVersion == 5,
                   document.pages.contains(where: { $0.nodes.contains { [.button, .link].contains($0.kind) } }) {
                    throw DocumentSerializationError.malformedInput
                }
            } catch { throw DocumentSerializationError.malformedInput }
        case 9:
            do {
                let strictDecoder = JSONDecoder()
                strictDecoder.userInfo[SiteForgeDecodingPolicy.strictCurrentSchema] = true
                strictDecoder.userInfo[SiteForgeDecodingPolicy.sourceDocumentSchema] = header.schemaVersion
                document = try strictDecoder.decode(CurrentEnvelope.self, from: data).document
                for pageIndex in document.pages.indices {
                    for nodeIndex in document.pages[pageIndex].nodes.indices {
                        let node = document.pages[pageIndex].nodes[nodeIndex]
                        guard let legacy = node.insertionProperty(LocalColorTokenBinding.legacyKey) else { continue }
                        guard [.frame, .section, .stack, .grid].contains(node.kind),
                              case .string(let raw) = legacy.value,
                              ColorTokenID(uuidString: raw) != nil,
                              node.properties.filter({ $0.key.rawValue == LocalColorTokenBinding.legacyKey }).count == 1,
                              node.insertionProperty(LocalColorTokenBinding.key(for: .fill)) == nil else {
                            throw DocumentSerializationError.malformedInput
                        }
                        document.pages[pageIndex].nodes[nodeIndex].properties.removeAll { $0.id == legacy.id }
                        document.pages[pageIndex].nodes[nodeIndex].properties.append(.init(
                            id: legacy.id, key: .init(rawValue: LocalColorTokenBinding.key(for: .fill)),
                            value: legacy.value, origin: legacy.origin))
                    }
                }
            } catch { throw DocumentSerializationError.malformedInput }
        case 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, currentSchemaVersion:
            do {
                let strictDecoder = JSONDecoder()
                strictDecoder.userInfo[SiteForgeDecodingPolicy.strictCurrentSchema] = true
                strictDecoder.userInfo[SiteForgeDecodingPolicy.sourceDocumentSchema] = header.schemaVersion
                document = try strictDecoder.decode(CurrentEnvelope.self, from: data).document
            } catch {
                throw DocumentSerializationError.malformedInput
            }
        default:
            throw DocumentSerializationError.unsupportedSchema(header.schemaVersion)
        }
        try checkpoint()
        if header.schemaVersion < ProjectPreferences.documentSchema, document.projectPreferences != nil {
            throw DocumentSerializationError.malformedInput
        }
        if header.schemaVersion < CanonicalReusableBoxAppearance.documentSchema,
           document.pages.contains(where: { $0.nodes.contains { $0.properties.contains(where: CanonicalReusableBoxAppearance.ownsDefinitionProperty) } }) {
            throw DocumentSerializationError.malformedInput
        }
        if header.schemaVersion < CanonicalComponentGraph.documentSchema,
           document.componentDefinitions.contains(where: { $0.nodes.contains { $0.kind == .component } }) {
            throw DocumentSerializationError.malformedInput
        }
        // SF-0804: SVG image assets need schema 27.
        if header.schemaVersion < CanonicalContainerQueries.documentSchema,
           document.imageAssets.contains(where: { $0.format == .svg }) {
            throw DocumentSerializationError.malformedInput
        }
        // OD-045 / SF-0805: project fonts need schema 27.
        if header.schemaVersion < FontAsset.documentSchema, !document.fontAssets.isEmpty {
            throw DocumentSerializationError.malformedInput
        }
        // OD-045 / SF-0803: video and audio files need schema 27.
        if header.schemaVersion < MediaAsset.documentSchema, !document.mediaAssets.isEmpty {
            throw DocumentSerializationError.malformedInput
        }
        // OD-038 / SF-1007: site languages need schema 27.
        if header.schemaVersion < SiteLocalization.documentSchema, document.localization != nil {
            throw DocumentSerializationError.malformedInput
        }
        // OD-035 / SF-1001: collections need schema 27.
        if header.schemaVersion < CanonicalCollections.documentSchema, !document.collections.isEmpty {
            throw DocumentSerializationError.malformedInput
        }
        // SF-1207 / SF-1107: website metadata version 2 and 3 fields need schema 27.
        if header.schemaVersion < CanonicalContainerQueries.documentSchema,
           document.websiteMetadata?.usesSocialFields == true || document.websiteMetadata?.usesCustomCode == true {
            throw DocumentSerializationError.malformedInput
        }
        if header.schemaVersion < CanonicalContainerQueries.documentSchema, document.pages.contains(where: { page in
            page.nodes.contains { node in node.properties.contains {
                $0.key.rawValue.hasPrefix(CanonicalContainerQueries.namespace)
                    || $0.key.rawValue.hasPrefix(CanonicalResponsiveAuditSuppression.namespace)
            } }
        }) { throw DocumentSerializationError.malformedInput }
        // OD-040 / SF-1103 and OD-039 / SF-1101: motion and interactions need schema 27.
        if header.schemaVersion < CanonicalMotion.documentSchema, document.pages.contains(where: { page in
            page.nodes.contains { node in node.properties.contains {
                $0.key.rawValue.hasPrefix(CanonicalMotion.prefix) || $0.key.rawValue.hasPrefix(CanonicalEventGraph.prefix)
                    || $0.key.rawValue.hasPrefix(CanonicalPageState.prefix) || $0.key.rawValue.hasPrefix(CanonicalOverlay.prefix)
            } }
        }) { throw DocumentSerializationError.malformedInput }
        if header.schemaVersion < CanonicalComponentVariants.documentSchema, document.pages.contains(where: { page in
            page.nodes.contains { node in node.properties.contains { property in
                property.key.rawValue.hasPrefix(CanonicalComponentVariants.namespace)
                    || CanonicalComponentVariants.isChoiceKey(property.key.rawValue)
            } }
        }) { throw DocumentSerializationError.malformedInput }
        if header.schemaVersion < CanonicalComponentSlot.contentSchema, document.pages.contains(where: { page in
            page.nodes.contains { node in
                (node.kind == .component && !node.childIDs.isEmpty) || node.properties.contains { property in
                    let key = property.key.rawValue
                    return key.hasPrefix(CanonicalComponentSlot.overrideNamespace) || key == CanonicalComponentSlot.supplyKey
                        || CanonicalComponentSlot.ruleKeys.contains(key)
                }
            }
        }) { throw DocumentSerializationError.malformedInput }
        if header.schemaVersion < CanonicalFlowGradient.documentSchema,
           document.pages.contains(where: { $0.nodes.contains { node in
               node.properties.contains { $0.key.rawValue.hasPrefix("style.flow.") || $0.key.rawValue.hasPrefix("style.glass.") || $0.key.rawValue.hasPrefix("content.qr.") }
           } }) { throw DocumentSerializationError.malformedInput }
        if header.schemaVersion < 21, document.pages.contains(where: { page in
            page.nodes.contains { owner in
                guard CanonicalPageFlow.role(owner) == .footer,
                      let contentID = CanonicalPageChrome.reference(CanonicalPageChrome.contentKey, on: owner) else { return false }
                return [CanonicalPageChrome.titleKey, CanonicalPageChrome.navigationKey].contains { key in
                    guard let id = CanonicalPageChrome.reference(key, on: owner), let node = page.nodes.first(where: { $0.id == id }) else { return false }
                    return node.parent != .node(contentID)
                }
            }
        }) { throw DocumentSerializationError.malformedInput }
        if header.schemaVersion < CanonicalComponentUsageNotes.documentSchema,
           document.pages.contains(where: { $0.nodes.contains { $0.properties.contains(where: CanonicalComponentUsageNotes.owns) } }) {
            throw DocumentSerializationError.malformedInput
        }
        if header.schemaVersion < 19, document.pages.contains(where: { page in page.nodes.contains { node in
            let sizing = node.properties.filter { $0.key.rawValue.hasPrefix(CanonicalSizingConstraints.prefix) }
            return !sizing.isEmpty && (![NodeKind.frame, .image].contains(node.kind) || sizing.contains {
                $0.key.rawValue == CanonicalSizingConstraints.prefix + "widthMode"
                    || $0.key.rawValue == CanonicalSizingConstraints.prefix + "heightMode"
            })
        } }) { throw DocumentSerializationError.malformedInput }
        if header.schemaVersion < 17, document.pages.contains(where: { page in page.nodes.contains { node in
            node.properties.contains { $0.key.rawValue.hasPrefix(CanonicalPageChrome.namespace) }
        } }) { throw DocumentSerializationError.malformedInput }
        if header.schemaVersion < 11, document.imageAssets.contains(where: { $0.organization != nil })
            || document.pages.contains(where: { page in page.nodes.contains { node in node.properties.contains {
                $0.key.rawValue.hasPrefix(CanonicalComponentChoice.namespace)
                    || $0.key.rawValue.hasPrefix(CanonicalComponentChoice.overrideNamespace)
            } } }) {
            throw DocumentSerializationError.malformedInput
        }
        if header.schemaVersion < 12, document.pages.contains(where: { page in page.nodes.contains { node in node.properties.contains {
            $0.key.rawValue.hasPrefix(CanonicalComponentMedia.namespace)
                || $0.key.rawValue.hasPrefix(CanonicalComponentMedia.overrideNamespace)
        } } }) { throw DocumentSerializationError.malformedInput }
        if header.schemaVersion < 13, document.pages.contains(where: { page in page.nodes.contains { node in node.properties.contains {
            $0.key.rawValue.hasPrefix(CanonicalComponentAction.namespace)
                || $0.key.rawValue.hasPrefix(CanonicalComponentAction.overrideNamespace)
        } } }) { throw DocumentSerializationError.malformedInput }
        if header.schemaVersion < 16, document.pages.contains(where: { page in page.nodes.contains { node in node.properties.contains {
            $0.key.rawValue.hasPrefix(CanonicalPageFlow.namespace) || $0.key.rawValue.hasPrefix(CanonicalPageFlow.navigationNamespace)
        } } }) { throw DocumentSerializationError.malformedInput }
        if header.schemaVersion < 15, document.pages.contains(where: { page in page.nodes.contains { node in node.properties.contains {
            $0.key.rawValue.hasPrefix(CanonicalComponentOrganization.namespace)
        } } }) { throw DocumentSerializationError.malformedInput }
        if header.schemaVersion < 14, document.pages.contains(where: { page in page.nodes.contains { node in node.properties.contains {
            $0.key.rawValue.hasPrefix(CanonicalComponentSlot.namespace)
        } } }) { throw DocumentSerializationError.malformedInput }
        if header.schemaVersion < 8, document.pages.contains(where: { page in
            page.nodes.contains { node in node.properties.contains {
                $0.key.rawValue.hasPrefix(CanonicalComponentText.namespace)
                    || $0.key.rawValue.hasPrefix(CanonicalComponentText.overrideNamespace)
            } }
        }) { throw DocumentSerializationError.malformedInput }
        if header.schemaVersion < 10, document.pages.contains(where: { page in
            page.nodes.contains { node in node.properties.contains {
                $0.key.rawValue.hasPrefix(CanonicalComponentVisibility.namespace)
                    || $0.key.rawValue.hasPrefix(CanonicalComponentVisibility.overrideNamespace)
            } }
        }) { throw DocumentSerializationError.malformedInput }
        if header.schemaVersion < 7,
           document.pages.contains(where: { $0.role == .componentDefinition || $0.nodes.contains(where: {
               $0.properties.contains { $0.key.rawValue.hasPrefix(CanonicalComponentReference.namespace) }
           }) }) {
            throw DocumentSerializationError.malformedInput
        }
        if header.schemaVersion < 6,
           document.pages.contains(where: { $0.nodes.contains { $0.kind.isLinkControl } }) {
            throw DocumentSerializationError.malformedInput
        }
        do {
            try document.validate(checkpoint: checkpoint)
            try CanonicalComponentOverrides.validateSerializableRetention(document, checkpoint: checkpoint)
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

// MARK: - Document migrations (SF-0309, ADR-0130)
// The registry orders and describes the upgrades `DocumentSerializer` already
// performs; it adds a dry-run report, loss checks and refusal, never a second
// conversion path. Still document schema 27.

/// One step in the closed registry of document schema upgrades.
struct DocumentMigrationStep: Equatable, Sendable {
    let fromSchema: Int
    let toSchema: Int
    /// Non-content description shown in the migration report.
    let summary: String
}

/// Why a stored document is not upgraded. Opening is refused and the file is
/// left unchanged; `recoverySuggestion` names the next step (SF-0309-004).
enum DocumentMigrationRefusal: Error, Equatable, LocalizedError, Sendable {
    case newerSchema(Int)
    case unsupportedSchema(Int)
    case malformed
    case lostContent(pages: Int, nodes: Int)
    case unstableResult

    var errorDescription: String? {
        switch self {
        case .newerSchema(let version):
            "This project uses document schema \(version), which is newer than this SiteForge (schema \(DocumentSerializer.currentSchemaVersion))."
        case .unsupportedSchema(let version):
            "Document schema \(version) cannot be upgraded by this SiteForge."
        case .malformed:
            "The project's document could not be read for upgrade."
        case .lostContent(let pages, let nodes):
            "Upgrading would lose \(pages) page(s) and \(nodes) element(s), so the project was not upgraded."
        case .unstableResult:
            "The upgraded document did not save and reopen identically, so the project was not upgraded."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .newerSchema:
            "Open it with the newer SiteForge that saved it. The file was not changed."
        case .unsupportedSchema, .malformed:
            "Restore a valid copy of the project or open a recovery snapshot. The file was not changed."
        case .lostContent, .unstableResult:
            "Keep the file as it is and report the problem. Nothing was changed or saved."
        }
    }

    var diagnosticCategory: String {
        switch self {
        case .newerSchema: "newer-schema"
        case .unsupportedSchema: "unsupported-schema"
        case .malformed: "malformed"
        case .lostContent: "lost-content"
        case .unstableResult: "unstable-result"
        }
    }
}

/// The dry-run result for one stored document: the steps that run and how the
/// content compares before and after. Counts only, never content (SF-0309-002).
struct DocumentMigrationReport: Equatable, Sendable {
    let sourceSchemaVersion: Int
    let targetSchemaVersion: Int
    let steps: [DocumentMigrationStep]
    let sourcePageCount: Int
    let sourceNodeCount: Int
    let migratedPageCount: Int
    let migratedNodeCount: Int
    let sourceByteCount: Int

    var needsMigration: Bool { sourceSchemaVersion < targetSchemaVersion }
    /// What the current schema requires in addition (for example the minimum
    /// root of a rootless legacy page). Nothing is removed: see `lostContent`.
    var addedPageCount: Int { max(0, migratedPageCount - sourcePageCount) }
    var addedNodeCount: Int { max(0, migratedNodeCount - sourceNodeCount) }

    var summary: String {
        guard needsMigration else { return "The project already uses document schema \(targetSchemaVersion)." }
        var text = "Upgraded from document schema \(sourceSchemaVersion) to \(targetSchemaVersion) in \(steps.count) step(s). "
            + "Kept \(sourcePageCount) page(s) and \(sourceNodeCount) element(s)"
        if addedPageCount > 0 || addedNodeCount > 0 {
            text += "; added \(addedPageCount) page(s) and \(addedNodeCount) element(s) the current schema requires"
        }
        return text + "."
    }

    /// One line per step, oldest first, for details and diagnostics exports.
    var stepLines: [String] { steps.map { "Schema \($0.fromSchema) to \($0.toSchema): \($0.summary)" } }
}

/// A dry-run report together with the stored document bytes it describes, so
/// the original can be kept before anything replaces it.
struct DocumentMigrationCandidate: Equatable, Sendable {
    let report: DocumentMigrationReport
    let sourceDocument: Data
    let dryRunNanoseconds: UInt64
}

/// SF-0309-008: schema numbers, durations and categories only.
struct DocumentMigrationDiagnosticRecord: Equatable, Sendable {
    enum Operation: String, Equatable, Sendable {
        case dryRun = "dry-run"
        case backup
    }

    let requirementID: String
    let operation: Operation
    let sourceSchemaVersion: Int
    let targetSchemaVersion: Int
    let durationNanoseconds: UInt64
    let failureCategory: String?
}

/// The closed, ordered registry of supported document upgrades
/// (SF-0309-001, SF-0309-003): exactly one step for every schema from the
/// minimum supported one to the current one, proven by `validateRegistry()`.
enum DocumentMigrations {
    /// The schema-upgrade slice of SF-0309 (ADR-0130). Importing external
    /// markup and assets (the rest of 002, and 006/007) is not covered yet.
    static let requirementIDs: Set<String> = ["SF-0309-001", "SF-0309-003", "SF-0309-004", "SF-0309-005", "SF-0309-008"]

    static let steps: [DocumentMigrationStep] = [
        .init(fromSchema: 1, toSchema: 2, summary: "Adds page routes, roles, provenance, creation kind, template identity and page roots."),
        .init(fromSchema: 2, toSchema: 3, summary: "Adds authored guides."),
        .init(fromSchema: 3, toSchema: 4, summary: "Adds Section, Stack and Grid structural elements (ADR-0015)."),
        .init(fromSchema: 4, toSchema: 5, summary: "Adds image assets."),
        .init(fromSchema: 5, toSchema: 6, summary: "Adds buttons and links."),
        .init(fromSchema: 6, toSchema: 7, summary: "Adds component definitions and references."),
        .init(fromSchema: 7, toSchema: 8, summary: "Adds component text bindings."),
        .init(fromSchema: 8, toSchema: 9, summary: "Adds local color tokens bound to fills."),
        .init(fromSchema: 9, toSchema: 10, summary: "Moves color-token bindings to fill, border and shadow keys and adds component visibility bindings."),
        .init(fromSchema: 10, toSchema: 11, summary: "Adds image asset organization and component choices."),
        .init(fromSchema: 11, toSchema: 12, summary: "Adds component media bindings."),
        .init(fromSchema: 12, toSchema: 13, summary: "Adds component action bindings."),
        .init(fromSchema: 13, toSchema: 14, summary: "Adds definition fallback slots."),
        .init(fromSchema: 14, toSchema: 15, summary: "Adds component property organization."),
        .init(fromSchema: 15, toSchema: 16, summary: "Adds connected page flow and navigation."),
        .init(fromSchema: 16, toSchema: 17, summary: "Adds page chrome."),
        .init(fromSchema: 17, toSchema: 18, summary: "Adds website metadata."),
        .init(fromSchema: 18, toSchema: 19, summary: "Adds opt-in responsive sizing modes."),
        .init(fromSchema: 19, toSchema: 20, summary: "Adds component usage notes."),
        .init(fromSchema: 20, toSchema: 21, summary: "Adds decorative effects, dark-appearance token colors and the footer chrome structure."),
        .init(fromSchema: 21, toSchema: 22, summary: "Adds project-scoped preferences."),
        .init(fromSchema: 22, toSchema: 23, summary: "Adds linked border, corner and shadow values to reusable styles."),
        .init(fromSchema: 23, toSchema: 24, summary: "Allows component instances inside definitions."),
        .init(fromSchema: 24, toSchema: 25, summary: "Adds instance-owned slot content and slot rules."),
        .init(fromSchema: 25, toSchema: 26, summary: "Adds property-only component variants."),
        .init(fromSchema: 26, toSchema: 27, summary: "Adds container queries, responsive-audit suppressions and the other optional schema-27 features."),
    ]

    /// Throws unless the registry is one contiguous chain from the minimum
    /// supported schema to the current one.
    static func validateRegistry() throws {
        var expected = DocumentSerializer.minimumSupportedSchemaVersion
        for step in steps {
            guard step.fromSchema == expected, step.toSchema == expected + 1, !step.summary.isEmpty else {
                throw DocumentMigrationRefusal.unsupportedSchema(step.fromSchema)
            }
            expected = step.toSchema
        }
        guard expected == DocumentSerializer.currentSchemaVersion else {
            throw DocumentMigrationRefusal.unsupportedSchema(expected)
        }
    }

    /// The ordered steps from `schema` to the current schema; empty when the
    /// schema is already current.
    static func path(from schema: Int) throws -> [DocumentMigrationStep] {
        guard schema <= DocumentSerializer.currentSchemaVersion else {
            throw DocumentMigrationRefusal.newerSchema(schema)
        }
        guard schema >= DocumentSerializer.minimumSupportedSchemaVersion else {
            throw DocumentMigrationRefusal.unsupportedSchema(schema)
        }
        let chain = steps.filter { $0.fromSchema >= schema }
        guard chain.count == DocumentSerializer.currentSchemaVersion - schema else {
            throw DocumentMigrationRefusal.unsupportedSchema(schema)
        }
        return chain
    }

    /// Reads one stored document without changing anything and reports what
    /// upgrading it does. Refuses when a stored page or element would be lost,
    /// or when the result does not save and reopen identically.
    static func dryRun(_ data: Data) throws -> DocumentMigrationReport {
        let schema: Int
        do { schema = try DocumentSerializer.schemaVersion(in: data) }
        catch { throw DocumentMigrationRefusal.malformed }
        let chain = try path(from: schema)
        let source = storedIdentifiers(in: data)
        let document: CanonicalDocument
        do {
            document = try DocumentSerializer.decode(data)
        } catch DocumentSerializationError.unsupportedSchema(let version) {
            throw version > DocumentSerializer.currentSchemaVersion
                ? DocumentMigrationRefusal.newerSchema(version)
                : DocumentMigrationRefusal.unsupportedSchema(version)
        } catch {
            throw DocumentMigrationRefusal.malformed
        }
        let migratedPages = Set(document.pages.map { $0.id.description.uppercased() })
        let migratedNodes = Set(document.pages.flatMap { page in page.nodes.map { $0.id.description.uppercased() } })
        let lostPages = source.pages.subtracting(migratedPages).count
        let lostNodes = source.nodes.subtracting(migratedNodes).count
        guard lostPages == 0, lostNodes == 0 else {
            throw DocumentMigrationRefusal.lostContent(pages: lostPages, nodes: lostNodes)
        }
        let reopened: CanonicalDocument
        do { reopened = try DocumentSerializer.decode(try DocumentSerializer.encode(document)) }
        catch { throw DocumentMigrationRefusal.unstableResult }
        guard reopened == document else { throw DocumentMigrationRefusal.unstableResult }
        return DocumentMigrationReport(
            sourceSchemaVersion: schema,
            targetSchemaVersion: DocumentSerializer.currentSchemaVersion,
            steps: chain,
            sourcePageCount: source.pages.count,
            sourceNodeCount: source.nodes.count,
            migratedPageCount: migratedPages.count,
            migratedNodeCount: migratedNodes.count,
            sourceByteCount: data.count
        )
    }

    /// Page and element identities as stored, read without the typed decoders
    /// so the comparison does not depend on the migration it checks.
    static func storedIdentifiers(in data: Data) -> (pages: Set<String>, nodes: Set<String>) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let document = object["document"] as? [String: Any],
              let pages = document["pages"] as? [[String: Any]] else {
            return ([], [])
        }
        var pageIDs = Set<String>()
        var nodeIDs = Set<String>()
        for page in pages {
            if let id = page["id"] as? String { pageIDs.insert(id.uppercased()) }
            for node in page["nodes"] as? [[String: Any]] ?? [] {
                if let id = node["id"] as? String { nodeIDs.insert(id.uppercased()) }
            }
        }
        return (pageIDs, nodeIDs)
    }
}
