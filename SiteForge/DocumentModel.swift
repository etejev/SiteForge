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
        [CanonicalImageStyle.namespace + "assetID", CanonicalImageFill.assetKey].compactMap {
            node.insertionStringProperty($0).flatMap(AssetID.init(uuidString:))
        } + node.properties.compactMap { property in
            guard CanonicalComponentMedia.overrideID(property.key.rawValue) != nil,
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
    static func navigationSettings(for surface: DocumentNode, page: DocumentPage) -> DocumentNode? {
        if [.header, .footer].contains(CanonicalPageFlow.role(surface)) {
            return reference(navigationKey, on: surface) == nil ? surface : nil
        }
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
                guard node.kind == kind, node.parent == .node(parent) else { throw ModelValidationError.invalidSemanticElementState }
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
struct LocalColorToken: Codable, Equatable, Identifiable, Sendable {
    let id: ColorTokenID
    var name: String
    var color: CanonicalSolidColor

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, name, color }

    init(id: ColorTokenID = ColorTokenID(), name: String, color: CanonicalSolidColor) {
        self.id = id; self.name = name; self.color = color
    }

    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder, when: SiteForgeDecodingPolicy.requiresExactKeys(decoder))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(ColorTokenID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        color = try values.decode(CanonicalSolidColor.self, forKey: .color)
    }

    var isValid: Bool {
        !name.isEmpty && name == name.trimmingCharacters(in: .whitespacesAndNewlines)
            && name.utf8.count <= 128 && !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && color.isValid
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
}

struct CanonicalReusableStyleIndex: Sendable {
    static let namespace = "style.reusable.v1."
    static let appliedKey = namespace + "applied"
    static let stateNamespace = "style.state.v1."
    let orderedDefinitions: [CanonicalReusableStyleDefinition]
    let byID: [ReusableStyleID: CanonicalReusableStyleDefinition]

    init(document: CanonicalDocument) throws {
        var definitions: [CanonicalReusableStyleDefinition] = []
        for node in document.pages.flatMap(\.nodes) {
            let names = node.properties.filter { $0.key.rawValue.hasPrefix(Self.namespace + "definition.") && $0.key.rawValue.hasSuffix(".name") }
            for nameProperty in names {
                let parts = nameProperty.key.rawValue.split(separator: ".")
                guard parts.count == 6, let id = ReusableStyleID(uuidString: String(parts[4])),
                      case .string(let name) = nameProperty.value,
                      Self.validName(name) else { throw ModelValidationError.invalidReusableStyleState }
                let prefix = Self.namespace + "definition.\(id.description)."
                let fillProperty = node.insertionProperty(prefix + "fill")
                let fill = node.insertionStringProperty(prefix + "fill").flatMap {
                    CanonicalSolidColor.parse(hexadecimal: $0)
                }
                let opacity = node.insertionNumberProperty(prefix + "opacity")
                guard fillProperty == nil || fill != nil,
                      opacity.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
                      fill != nil || opacity != nil else {
                    throw ModelValidationError.invalidReusableStyleState
                }
                definitions.append(.init(id: id, name: name, fill: fill, opacity: opacity))
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
                      byID[id] != nil, ["name", "fill", "opacity"].contains(String(parts[5])) else {
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

/// SF-1207: optional fields are omitted intent, never equivalent authored
/// literals. Effective defaults/provenance are resolved without rewriting them.
struct PageWebsiteMetadata: Codable, Equatable, Sendable {
    let pageID: PageID
    var title: String?
    var description: String?
    var allowsIndexing: Bool?

    init(pageID: PageID, title: String? = nil, description: String? = nil, allowsIndexing: Bool? = nil) {
        self.pageID = pageID; self.title = title; self.description = description; self.allowsIndexing = allowsIndexing
    }
    var isEmpty: Bool { title == nil && description == nil && allowsIndexing == nil }
    var isValid: Bool {
        WebsiteMetadata.validText(title, maximumBytes: 512)
            && WebsiteMetadata.validText(description, maximumBytes: 2_048)
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case pageID, title, description, allowsIndexing }
    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pageID = try values.decode(PageID.self, forKey: .pageID)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        allowsIndexing = try values.decodeIfPresent(Bool.self, forKey: .allowsIndexing)
        guard isValid else { throw ModelValidationError.invalidWebsiteMetadata }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(pageID, forKey: .pageID)
        try values.encode(title, forKey: .title)
        try values.encode(description, forKey: .description)
        try values.encode(allowsIndexing, forKey: .allowsIndexing)
    }
}

struct WebsiteMetadata: Codable, Equatable, Sendable {
    static let currentVersion = 1
    let version: Int
    var siteName: String?
    var titlePattern: String?
    var defaultDescription: String?
    var faviconAssetID: AssetID?
    var allowsIndexing: Bool?
    var pages: [PageWebsiteMetadata]

    init(siteName: String? = nil, titlePattern: String? = nil, defaultDescription: String? = nil,
         faviconAssetID: AssetID? = nil, allowsIndexing: Bool? = nil, pages: [PageWebsiteMetadata] = []) {
        version = Self.currentVersion
        self.siteName = siteName; self.titlePattern = titlePattern; self.defaultDescription = defaultDescription
        self.faviconAssetID = faviconAssetID; self.allowsIndexing = allowsIndexing
        self.pages = pages.sorted { $0.pageID.description < $1.pageID.description }
    }
    var isEmpty: Bool {
        siteName == nil && titlePattern == nil && defaultDescription == nil
            && faviconAssetID == nil && allowsIndexing == nil && pages.isEmpty
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
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, siteName, titlePattern, defaultDescription, faviconAssetID, allowsIndexing, pages
    }
    init(from decoder: Decoder) throws {
        try requireExactKeys(CodingKeys.self, in: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        siteName = try values.decodeIfPresent(String.self, forKey: .siteName)
        titlePattern = try values.decodeIfPresent(String.self, forKey: .titlePattern)
        defaultDescription = try values.decodeIfPresent(String.self, forKey: .defaultDescription)
        faviconAssetID = try values.decodeIfPresent(AssetID.self, forKey: .faviconAssetID)
        allowsIndexing = try values.decodeIfPresent(Bool.self, forKey: .allowsIndexing)
        pages = try values.decode([PageWebsiteMetadata].self, forKey: .pages)
        guard isValid else { throw ModelValidationError.invalidWebsiteMetadata }
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
    static func resolve(page: DocumentPage, document: CanonicalDocument) -> ResolvedWebsiteMetadata {
        let metadata = document.websiteMetadata
        let overrides = metadata?.pages.first { $0.pageID == page.id }
        let siteName = metadata?.siteName ?? document.pages.first(where: { $0.role == .home })?.name ?? "Untitled Site"
        let pattern = metadata?.titlePattern ?? "{page}"
        // Substitute once: an authored site/page name containing braces is text,
        // not a second template evaluation or executable expression.
        let title = overrides?.title ?? pattern.components(separatedBy: "{page}")
            .map { $0.components(separatedBy: "{site}").joined(separator: siteName) }.joined(separator: page.name)
        return .init(siteName: siteName, title: title,
                     description: overrides?.description ?? metadata?.defaultDescription,
                     faviconAssetID: metadata?.faviconAssetID,
                     allowsIndexing: overrides?.allowsIndexing ?? metadata?.allowsIndexing ?? true,
                     titleSource: overrides?.title != nil ? .authored : (metadata?.titlePattern != nil ? .inherited : .defaulted),
                     descriptionSource: overrides?.description != nil ? .authored
                        : (metadata?.defaultDescription != nil ? .inherited : .omitted))
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

    init(
        id: DocumentID = DocumentID(),
        revision: UInt64 = 0,
        creationKind: ProjectCreationKind = .blank,
        templateID: TemplateID? = nil,
        pages: [DocumentPage]? = nil,
        guides: [AuthoredGuide] = [],
        imageAssets: [ImageAsset] = [],
        colorTokens: [LocalColorToken] = [],
        websiteMetadata: WebsiteMetadata? = nil
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
    }


    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, revision, creationKind, templateID, pages, guides, imageAssets, colorTokens, websiteMetadata
    }
    private enum PreMetadataCodingKeys: String, CodingKey, CaseIterable {
        case id, revision, creationKind, templateID, pages, guides, imageAssets, colorTokens
    }

    init(from decoder: Decoder) throws {
        if (decoder.userInfo[SiteForgeDecodingPolicy.sourceDocumentSchema] as? Int ?? 18) < 18 {
            try requireExactKeys(PreMetadataCodingKeys.self, in: decoder, when: SiteForgeDecodingPolicy.requiresExactKeys(decoder))
        } else {
            try requireExactKeys(CodingKeys.self, in: decoder, when: SiteForgeDecodingPolicy.requiresExactKeys(decoder))
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
        }) {
            return // The definition-scoped validator owns exposed bindings.
        }
        guard node.kind == .component, properties.contains(where: { $0.key.rawValue == key }),
              properties.allSatisfy({ $0.key.rawValue == key
                  || CanonicalComponentText.overrideID($0.key.rawValue) != nil
                  || CanonicalComponentVisibility.overrideID($0.key.rawValue) != nil
                  || CanonicalComponentChoice.overrideID($0.key.rawValue) != nil
                  || CanonicalComponentMedia.overrideID($0.key.rawValue) != nil
                  || CanonicalComponentAction.overrideID($0.key.rawValue) != nil }),
              definitionID(for: node) != nil, node.childIDs.isEmpty else {
            throw ModelValidationError.invalidComponentReference
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
        for property in node.properties where property.key.rawValue.hasPrefix(overrideNamespace) {
            guard node.kind == .component, !inDefinition,
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
        let newNodes = Dictionary(uniqueKeysWithValues: new.websitePages.flatMap(\.nodes).map { ($0.id, $0) })
        for instance in old.websitePages.flatMap(\.nodes) {
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
            guard node.kind == .component, !inDefinition, overrideID(property.key.rawValue) != nil,
                  property.origin == .authored, case .string(let raw) = property.value,
                  ImageFitMode(rawValue: raw) != nil else { throw ModelValidationError.invalidComponentReference }
        }
    }
    static func validateTransition(from old: CanonicalDocument, to new: CanonicalDocument) throws {
        let oldDefinitions = Dictionary(uniqueKeysWithValues: old.componentDefinitions.map { ($0.id, $0) })
        let newDefinitions = Dictionary(uniqueKeysWithValues: new.componentDefinitions.map { ($0.id, $0) })
        let newNodes = Dictionary(uniqueKeysWithValues: new.websitePages.flatMap(\.nodes).map { ($0.id, $0) })
        for instance in old.websitePages.flatMap(\.nodes) {
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
            guard node.kind == .component, !inDefinition, overrideID(property.key.rawValue) != nil,
                  property.origin == .authored, case .string(let raw) = property.value,
                  let assetID = AssetID(uuidString: raw), assetID.description == raw else {
                throw ModelValidationError.invalidComponentReference
            }
        }
    }
    static func validateTransition(from old: CanonicalDocument, to new: CanonicalDocument) throws {
        let oldDefinitions = Dictionary(uniqueKeysWithValues: old.componentDefinitions.map { ($0.id, $0) })
        let newDefinitions = Dictionary(uniqueKeysWithValues: new.componentDefinitions.map { ($0.id, $0) })
        let newNodes = Dictionary(uniqueKeysWithValues: new.websitePages.flatMap(\.nodes).map { ($0.id, $0) })
        for instance in old.websitePages.flatMap(\.nodes) {
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
            guard node.kind == .component, !inDefinition, overrideID(property.key.rawValue) != nil,
                  property.origin == .authored, case .string(let raw) = property.value, decode(raw) != nil else {
                throw ModelValidationError.invalidComponentReference
            }
        }
    }
    static func validateTransition(from old: CanonicalDocument, to new: CanonicalDocument) throws {
        let definitions = Dictionary(uniqueKeysWithValues: new.componentDefinitions.map { ($0.id, $0) })
        let instances = Dictionary(uniqueKeysWithValues: new.websitePages.flatMap(\.nodes).map { ($0.id, $0) })
        for oldInstance in old.websitePages.flatMap(\.nodes) {
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
}

/// SF-0903 bounded fallback slice. No encoded node graph or shared mutable
/// content is introduced. Supplied instance ownership remains gated by OD-018.
enum CanonicalComponentSlot {
    static let namespace = "component.exposedSlot.v1."
    static let unsupportedOverrideNamespace = "component.instance.v1.slot."
    static let metadataKeys = Set([namespace + "id", namespace + "label", namespace + "type"])
    static let supportedKinds: Set<NodeKind> = [.frame, .section, .stack, .grid]

    static func property(on node: DocumentNode) -> ExposedComponentSlotProperty? {
        guard supportedKinds.contains(node.kind),
              let raw = node.insertionStringProperty(namespace + "id"),
              let id = ComponentSlotPropertyID(uuidString: raw), id.description == raw,
              let label = node.insertionStringProperty(namespace + "label"), CanonicalComponentText.validLabel(label),
              node.insertionStringProperty(namespace + "type") == "ordered-fallback-children" else { return nil }
        return .init(id: id, sourceNodeID: node.id, label: label, defaultChildIDs: node.childIDs)
    }
    static func properties(in definition: DocumentPage) -> [ExposedComponentSlotProperty] {
        definition.nodes.compactMap(property)
    }
    static func validate(_ node: DocumentNode, inDefinition: Bool) throws {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix(namespace) }
        guard !owned.isEmpty else { return }
        guard inDefinition, Set(owned.map(\.key.rawValue)) == metadataKeys,
              owned.count == metadataKeys.count, owned.allSatisfy({ $0.origin == .authored }),
              property(on: node) != nil else { throw ModelValidationError.invalidComponentReference }
    }
    static func validateTransition(from old: CanonicalDocument, to new: CanonicalDocument) throws {
        let newInstances = Dictionary(uniqueKeysWithValues: new.websitePages.flatMap(\.nodes).map { ($0.id, $0) })
        let liveDefinitionIDs = Set(old.websitePages.flatMap(\.nodes).compactMap { node -> PageID? in
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
            guard node.kind == .component, !inDefinition, overrideID(property.key.rawValue) != nil,
                  property.origin == .authored, case .boolean = property.value else {
                throw ModelValidationError.invalidComponentReference
            }
        }
    }
    static func validateTransition(from old: CanonicalDocument, to new: CanonicalDocument) throws {
        let oldDefinitions = Dictionary(uniqueKeysWithValues: old.componentDefinitions.map { ($0.id, $0) })
        let newDefinitions = Dictionary(uniqueKeysWithValues: new.componentDefinitions.map { ($0.id, $0) })
        let newNodes = Dictionary(uniqueKeysWithValues: new.websitePages.flatMap(\.nodes).map { ($0.id, $0) })
        for instance in old.websitePages.flatMap(\.nodes) {
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
        for instance in document.websitePages.flatMap(\.nodes) where instance.kind == .component {
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
        guard textProperties.count + visibilityProperties.count + choiceProperties.count + mediaProperties.count + actionProperties.count <= maximumOverridesPerInstance else {
            throw ModelValidationError.invalidComponentReference
        }
        guard let definition = (definitions ?? document.componentDefinitions).first(where: { $0.id == definitionID }) else {
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
            return (unresolvedText + unresolvedVisibility + unresolvedChoice + unresolvedMedia + unresolvedAction).sorted { $0.property.stableDescription < $1.property.stableDescription }
        }

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
        for exposed in CanonicalComponentSlot.properties(in: definition) {
            result.append(.init(property: .slot(exposed.id),
                path: .init(definitionID: definitionID, sourceNodeID: exposed.sourceNodeID, property: .slot(exposed.id)),
                label: exposed.label, inheritedValue: .slotFallback(exposed.defaultChildIDs),
                effectiveValue: .slotFallback(exposed.defaultChildIDs), resolution: .inherited))
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
    case invalidImageReference
    case invalidColorToken
    case invalidSizingConstraints
    case invalidComponentReference

    var errorDescription: String? {
        switch self {
        case .componentTextIntentWouldBeLost: "This text property has authored instance values. Reset those values or detach the affected instances before removing its source or binding."
        case .componentVisibilityIntentWouldBeLost: "This visibility property has authored instance values. Reset them or detach affected instances before removing its source or binding."
        case .revisionNotIncrementable: "The document revision cannot accept another transaction."
        case .invalidComponentReference: "The component reference is malformed or belongs to an incompatible object."
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
        case .invalidImageReference: "An Image node must reference an existing canonical image asset."
        case .invalidWebsiteMetadata: "Website metadata must contain valid values and unique existing page identities."
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
                  width.isFinite, width > 0, width <= 100, case .string(let style)? = values["border.style"],
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
            for node in page.nodes { try LocalColorTokenBinding.validate(node) }
        }
        guard pages.flatMap(\.nodes).filter({ CanonicalIsolationRoot.property(in: $0) != nil }).count <= 1 else {
            throw ModelValidationError.invalidIsolationRootState
        }
        _ = try CanonicalReusableStyleIndex(document: self)
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
                  root.kind.acceptsAuthoredChildren,
                  !nodes.contains(where: { $0.kind == .component }) else {
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
            try CanonicalPageChrome.validate(node, in: self)
            try CanonicalComponentReference.validate(node)
            try CanonicalComponentText.validate(node, inDefinition: role == .componentDefinition)
            try CanonicalComponentVisibility.validate(node, inDefinition: role == .componentDefinition)
            try CanonicalComponentChoice.validate(node, inDefinition: role == .componentDefinition)
            try CanonicalComponentMedia.validate(node, inDefinition: role == .componentDefinition)
            try CanonicalComponentAction.validate(node, inDefinition: role == .componentDefinition)
            try CanonicalComponentSlot.validate(node, inDefinition: role == .componentDefinition)
            try CanonicalComponentOrganization.validate(node, inDefinition: role == .componentDefinition)
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
            try CanonicalResponsiveGeometryNamespaceValidator.validate(node)
            try CanonicalResponsiveContainerNamespaceValidator.validate(node)
            try CanonicalResponsiveVisibilityNamespaceValidator.validate(node)
            try CanonicalFluidValueNamespaceValidator.validate(node)
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
    static let currentSchemaVersion = 19
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
        case 10, 11, 12, 13, 14, 15, 16, 17, 18, currentSchemaVersion:
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
