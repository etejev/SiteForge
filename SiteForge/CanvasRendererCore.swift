import CryptoKit
import Foundation

enum CanvasRenderSurfaceDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "render-surface"
}
typealias CanvasRenderSurfaceID = StableIdentifier<CanvasRenderSurfaceDomain>

enum CanvasOverlayDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "editor-overlay"
}
typealias CanvasOverlayID = StableIdentifier<CanvasOverlayDomain>

enum CanvasAccessibilityDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "render-accessibility"
}
typealias CanvasAccessibilityID = StableIdentifier<CanvasAccessibilityDomain>

struct CanvasRenderRequestIdentity: Codable, Hashable, Sendable {
    let documentID: DocumentID
    let revision: UInt64
    let sceneID: CanvasViewportSceneID
    let sceneGeneration: UInt64
    let viewportGeneration: UInt64
    let scale: CanvasPixelRatio
}

enum CanvasPaintStyle: String, Codable, Hashable, Sendable {
    case canvas, page, container, frameSurface, sectionSurface, stackSurface, gridSurface, imagePlaceholder, textPlaceholder
}

enum CanvasBorderStyle: String, Codable, Hashable, Sendable { case solid, dashed, dotted }

struct CanvasAuthoredBorder: Codable, Hashable, Sendable {
    let rgba: [Double]
    let width: Double
    let style: CanvasBorderStyle
    var isValid: Bool { rgba.count == 4 && rgba.allSatisfy { $0.isFinite && (0...1).contains($0) } && width.isFinite && width > 0 && width <= 100 }
}

struct CanvasAuthoredShadow: Codable, Hashable, Sendable {
    let rgba: [Double]
    let offsetX: Double
    let offsetY: Double
    let blur: Double
    let spread: Double
    var isValid: Bool {
        rgba.count == 4 && rgba.allSatisfy { $0.isFinite && (0...1).contains($0) }
            && [offsetX, offsetY, blur, spread].allSatisfy(\.isFinite)
            && (-10_000...10_000).contains(offsetX)
            && (-10_000...10_000).contains(offsetY)
            && (0...1_000).contains(blur)
            && (-1_000...1_000).contains(spread)
    }
}

enum CanvasTextAlignment: String, Codable, Hashable, Sendable { case leading, center, trailing }

/// Derived paint capacity, not authored overflow state. The native text layer
/// and static title projection share the same inset and complete-line budget.
enum CanvasTextLayoutPolicy {
    static let horizontalInset: Double = 4
    static func visibleLineCapacity(height: Double, lineHeight: Double) -> Int {
        guard height.isFinite, lineHeight.isFinite, height > 0, lineHeight > 0 else { return 0 }
        return max(1, Int(min(1_000_000, floor(height / lineHeight))))
    }
}

struct CanvasTypography: Codable, Hashable, Sendable {
    let authoredFamily: String
    let resolvedFamily: String
    let weight: String
    let size: Double
    let lineHeight: Double
    let tracking: Double
    let alignment: CanvasTextAlignment
    let usesFallback: Bool
    var foregroundRGBA: [Double]? = nil
    var isValid: Bool {
        !authoredFamily.isEmpty && !resolvedFamily.isEmpty
            && [size, lineHeight, tracking].allSatisfy(\.isFinite)
            && (1...1_000).contains(size) && (1...2_000).contains(lineHeight)
            && lineHeight >= size * 0.5 && (-100...100).contains(tracking)
            && (foregroundRGBA == nil || (foregroundRGBA?.count == 4 && foregroundRGBA?.allSatisfy { $0.isFinite && (0...1).contains($0) } == true))
    }
}

/// Immutable, renderer-facing fill data. This is derived from the canonical
/// `style.fill.layers.v1` properties while building a scene snapshot; it is
/// never edited by the renderer and therefore cannot race geometry adoption.
struct CanvasGradientStop: Codable, Hashable, Sendable {
    /// Renderer snapshots use raw stable UUID values so this headless canvas
    /// contract remains independent of the canonical command/model slice.
    let id: UUID
    let position: Double
    let rgba: [Double]

    var isValid: Bool {
        position.isFinite && (0...1).contains(position)
            && rgba.count == 4 && rgba.allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

enum CanvasAuthoredFillKind: String, Codable, Hashable, Sendable {
    case solid
    case linearGradient
}

struct CanvasAuthoredFillLayer: Codable, Hashable, Sendable {
    let id: UUID
    let kind: CanvasAuthoredFillKind
    let isEnabled: Bool
    let rgba: [Double]?
    /// Degrees are normalized to [0, 360), where 0 is left-to-right in the
    /// canonical top-left/Y-down viewport coordinate convention.
    let angleDegrees: Double?
    /// Stable authored order is retained here. Interpolation uses a local
    /// stable position sort so the author can reorder equal/overlapping stops.
    let stops: [CanvasGradientStop]

    var isValid: Bool {
        switch kind {
        case .solid:
            return rgba?.count == 4 && rgba!.allSatisfy { $0.isFinite && (0...1).contains($0) }
                && angleDegrees == nil && stops.isEmpty
        case .linearGradient:
            return rgba == nil && (angleDegrees?.isFinite ?? false)
                && stops.count >= 2 && Set(stops.map(\.id)).count == stops.count
                && stops.allSatisfy(\.isValid)
        }
    }
}

/// Pure compositing policy shared by focused renderer tests and native paint
/// preparation. Alpha uses ordinary source-over compositing; object opacity is
/// intentionally applied by the caller exactly once after all layer values.
enum CanvasAuthoredFillCompositor {
    /// The gradient stop list is authored and persisted in identity/order
    /// order. Sampling deliberately uses this local stable position order so
    /// rendering cannot mutate or reinterpret the canonical stop list.
    static func interpolationStops(for layer: CanvasAuthoredFillLayer) -> [CanvasGradientStop] {
        layer.stops.enumerated().sorted {
            $0.element.position == $1.element.position ? $0.offset < $1.offset : $0.element.position < $1.element.position
        }.map(\.element)
    }

    /// A unit-space direction for the top-left/Y-down canvas convention.
    /// Zero degrees therefore runs left-to-right and ninety degrees runs
    /// top-to-bottom. Native paint and deterministic sampling use this one
    /// conversion rather than applying independent Core Graphics flips.
    static func normalizedGradientLine(angleDegrees: Double) -> (start: (x: Double, y: Double), end: (x: Double, y: Double)) {
        let radians = angleDegrees * .pi / 180
        let dx = cos(radians), dy = sin(radians)
        let extent = max(Double.leastNonzeroMagnitude, abs(dx) + abs(dy))
        return (
            start: (x: 0.5 - dx / (2 * extent), y: 0.5 - dy / (2 * extent)),
            end: (x: 0.5 + dx / (2 * extent), y: 0.5 + dy / (2 * extent))
        )
    }

    /// Object opacity is applied once after the complete authored layer
    /// stack. Layer colors remain straight RGBA, which matches CGContext's
    /// alpha compositing and prevents a layer alpha from being multiplied
    /// twice during renderer adoption.
    static func applyingObjectOpacity(_ rgba: [Double], opacity: Double) -> [Double]? {
        guard rgba.count == 4, rgba.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              opacity.isFinite, (0...1).contains(opacity) else { return nil }
        return [rgba[0], rgba[1], rgba[2], rgba[3] * opacity]
    }

    static func resolvedColor(
        layers: [CanvasAuthoredFillLayer],
        atNormalizedPoint point: (x: Double, y: Double)
    ) -> [Double]? {
        var result: [Double]?
        for layer in layers where layer.isEnabled {
            guard let source = color(for: layer, atNormalizedPoint: point) else { continue }
            result = composite(source: source, over: result)
        }
        return result
    }

    static func color(for layer: CanvasAuthoredFillLayer, atNormalizedPoint point: (x: Double, y: Double)) -> [Double]? {
        guard layer.isValid else { return nil }
        switch layer.kind {
        case .solid: return layer.rgba
        case .linearGradient:
            guard let angle = layer.angleDegrees else { return nil }
            let line = normalizedGradientLine(angleDegrees: angle)
            let dx = line.end.x - line.start.x, dy = line.end.y - line.start.y
            let denominator = dx * dx + dy * dy
            guard denominator > 0 else { return nil }
            let projection = ((point.x - line.start.x) * dx + (point.y - line.start.y) * dy) / denominator
            let ordered = interpolationStops(for: layer)
            guard let first = ordered.first, let last = ordered.last else { return nil }
            if projection <= first.position { return first.rgba }
            if projection >= last.position { return last.rgba }
            for pair in zip(ordered, ordered.dropFirst()) where projection <= pair.1.position {
                let span = pair.1.position - pair.0.position
                let t = span == 0 ? 1 : (projection - pair.0.position) / span
                return zip(pair.0.rgba, pair.1.rgba).map { $0 + ($1 - $0) * t }
            }
            return last.rgba
        }
    }

    private static func composite(source: [Double], over destination: [Double]?) -> [Double] {
        guard let destination else { return source }
        let sourceAlpha = source[3], destinationAlpha = destination[3]
        let inverseSourceAlpha = 1 - sourceAlpha
        let destinationContribution = destinationAlpha * inverseSourceAlpha
        let outputAlpha = sourceAlpha + destinationContribution
        guard outputAlpha > 0 else { return [0, 0, 0, 0] }
        var result = [Double](repeating: 0, count: 4)
        for channel in 0..<3 {
            let sourceContribution = source[channel] * sourceAlpha
            let backgroundContribution = destination[channel] * destinationContribution
            result[channel] = (sourceContribution + backgroundContribution) / outputAlpha
        }
        result[3] = outputAlpha
        return result
    }
}

struct CanvasRenderObject: Codable, Hashable, Sendable {
    let id: NodeID
    let parentNodeID: NodeID?
    let pageFlowRole: PageFlowRole?
    let frame: WorldRect
    let clipRect: WorldRect?
    let paintOrder: Int
    let style: CanvasPaintStyle
    let isVisible: Bool
    let accessibilityLabel: String
    let accessibilityHelp: String?
    let plainText: String?
    /// A canonical node name is safe to render as authored chrome. It is
    /// deliberately distinct from editor-only selection labels and handles.
    let displayName: String?
    /// Authored color is distinct from `CanvasPaintStyle` (the bounded
    /// renderer's semantic fallback) and from editor-only overlays.
    let fillRGBA: [Double]?
    /// Authoritative ordered layers for v1 documents. An empty value means
    /// legacy scene input, where `fillRGBA` retains compatibility only.
    let fillLayers: [CanvasAuthoredFillLayer]
    let opacity: Double
    let border: CanvasAuthoredBorder?
    let cornerRadius: Double
    let shadow: CanvasAuthoredShadow?
    let typography: CanvasTypography?
    let imageAssetID: AssetID?
    let imageData: Data?
    let imagePixelWidth: Int?
    let imagePixelHeight: Int?
    let imageFitMode: CanvasImageFitMode?
    let imageFocalX: Double
    let imageFocalY: Double
    /// Read-only canonical semantic provenance carried into immutable Preview
    /// snapshots. It is metadata, never a rendered/editor-chrome pixel.
    let semanticElement: String?
    /// Validated navigation intent for local Preview. Authoring canvas input
    /// never follows this value, and static output resolves the same canonical
    /// target independently at its trust boundary.
    let previewLink: CanvasPreviewLink?
    let navigation: PageNavigationSnapshot?
    let navigationOwnerID: NodeID?

    /// Canvas navigation retains a paint-only Menu label. Native Preview
    /// replaces that proxy with a real control, never an overlaid text host
    /// that duplicates its label and intercepts its pointer surface.
    var paintsStandalonePreviewText: Bool { plainText != nil && navigation == nil }
    /// Pure paint has no independent visitor action. Page chrome supplies its
    /// semantic container around these surfaces and the real child controls.
    var isNativePreviewDecoration: Bool {
        plainText == nil && navigation == nil && imageAssetID == nil && previewLink == nil
    }

    init(
        id: NodeID,
        frame: WorldRect,
        clipRect: WorldRect?,
        paintOrder: Int,
        style: CanvasPaintStyle,
        isVisible: Bool,
        accessibilityLabel: String,
        accessibilityHelp: String? = nil,
        plainText: String? = nil,
        displayName: String? = nil,
        fillRGBA: [Double]? = nil,
        fillLayers: [CanvasAuthoredFillLayer] = [],
        opacity: Double = 1,
        border: CanvasAuthoredBorder? = nil,
        cornerRadius: Double = 0,
        shadow: CanvasAuthoredShadow? = nil,
        typography: CanvasTypography? = nil,
        imageAssetID: AssetID? = nil,
        imageData: Data? = nil,
        imagePixelWidth: Int? = nil,
        imagePixelHeight: Int? = nil,
        imageFitMode: CanvasImageFitMode? = nil,
        imageFocalX: Double = 0.5,
        imageFocalY: Double = 0.5,
        semanticElement: String? = nil,
        previewLink: CanvasPreviewLink? = nil,
        navigation: PageNavigationSnapshot? = nil,
        navigationOwnerID: NodeID? = nil,
        parentNodeID: NodeID? = nil,
        pageFlowRole: PageFlowRole? = nil
    ) {
        self.id = id
        self.parentNodeID = parentNodeID
        self.pageFlowRole = pageFlowRole
        self.frame = frame
        self.clipRect = clipRect
        self.paintOrder = paintOrder
        self.style = style
        self.isVisible = isVisible
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHelp = accessibilityHelp
        self.plainText = plainText
        self.displayName = displayName
        self.fillRGBA = fillRGBA
        self.fillLayers = fillLayers
        self.opacity = opacity
        self.border = border
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.typography = typography
        self.imageAssetID = imageAssetID
        self.imageData = imageData
        self.imagePixelWidth = imagePixelWidth
        self.imagePixelHeight = imagePixelHeight
        self.imageFitMode = imageFitMode
        self.imageFocalX = imageFocalX
        self.imageFocalY = imageFocalY
        self.semanticElement = semanticElement
        self.previewLink = previewLink
        self.navigation = navigation
        self.navigationOwnerID = navigationOwnerID
    }
}

struct CanvasPreviewLink: Codable, Hashable, Sendable {
    let target: CanonicalLinkTarget
    let context: CanonicalLinkContext
    let isMissing: Bool
}

enum CanvasImageFitMode: String, Codable, Hashable, Sendable {
    case fit, fill, stretch
}

/// One deterministic authored-image layout contract shared by tile drawing
/// and headless renderer evidence. Geometry remains top-left/Y-down; native
/// image decoding performs its single API-coordinate reflection only at draw.
enum CanvasImageLayout {
    static func destinationRect(
        source: WorldSize,
        bounds: WorldRect,
        mode: CanvasImageFitMode,
        focalX: Double,
        focalY: Double
    ) -> WorldRect? {
        guard source.width.isFinite, source.height.isFinite,
              source.width > 0, source.height > 0,
              bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              bounds.size.width.isFinite, bounds.size.height.isFinite,
              bounds.size.width > 0, bounds.size.height > 0,
              focalX.isFinite, focalY.isFinite,
              (0...1).contains(focalX), (0...1).contains(focalY) else { return nil }
        if mode == .stretch { return bounds }
        let xScale = bounds.size.width / source.width
        let yScale = bounds.size.height / source.height
        let scale = mode == .fit ? min(xScale, yScale) : max(xScale, yScale)
        let size = WorldSize(width: source.width * scale, height: source.height * scale)
        // Focal positioning is a crop control and therefore applies only to
        // Fill. Fit always uses calm deterministic centering in its letterbox.
        let x = mode == .fill ? focalX : 0.5
        let y = mode == .fill ? focalY : 0.5
        return WorldRect(
            origin: WorldPoint(
                x: bounds.origin.x + (bounds.size.width - size.width) * x,
                y: bounds.origin.y + (bounds.size.height - size.height) * y
            ),
            size: size
        )
    }
}

struct CanvasEditorOverlay: Codable, Hashable, Sendable {
    let id: CanvasOverlayID
    let objectID: NodeID
    let frame: WorldRect
    let kind: String
    /// Selection context is editor-only and intentionally excluded from the
    /// authored render scene, package, history, preview, and export snapshots.
    let label: String?

    init(
        id: CanvasOverlayID,
        objectID: NodeID,
        frame: WorldRect,
        kind: String,
        label: String? = nil
    ) {
        self.id = id
        self.objectID = objectID
        self.frame = frame
        self.kind = kind
        self.label = label
    }
}

struct CanvasRenderSceneSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let identity: CanvasRenderRequestIdentity
    let surfaceID: CanvasRenderSurfaceID
    let objects: [CanvasRenderObject]
    /// Appearance of the structural page surface, not a selectable object.
    /// Its bounds are derived from the same immutable artboard snapshot.
    let pageBackground: CanvasRenderObject?
    var paintObjects: [CanvasRenderObject] { pageBackground.map { [$0] + objects } ?? objects }

    init(
        schemaVersion: Int = currentSchemaVersion,
        identity: CanvasRenderRequestIdentity,
        surfaceID: CanvasRenderSurfaceID,
        objects: [CanvasRenderObject],
        pageBackground: CanvasRenderObject? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.identity = identity
        self.surfaceID = surfaceID
        self.objects = objects
        self.pageBackground = pageBackground
    }
}

struct CanvasEditorOverlaySnapshot: Equatable, Sendable {
    let identity: CanvasRenderRequestIdentity
    let overlays: [CanvasEditorOverlay]
}

/// Navigation uses authored units for layout and display units for its SwiftUI
/// proposal. A paint-only scale must never retain a world-sized hit/layout box.
struct CanvasPreviewNavigationGeometry: Equatable, Sendable {
    let worldSize: WorldSize
    let displaySize: WorldSize
    let displayOrigin: WorldPoint

    init?(frame: WorldRect, padding: Double, rowHeight: Double, scale: Double) {
        guard padding.isFinite, padding >= 0, rowHeight.isFinite, rowHeight > 0,
              scale.isFinite, scale > 0,
              frame.size.width.isFinite, frame.size.height.isFinite,
              frame.size.width > padding * 2, frame.size.height > padding * 2 else { return nil }
        worldSize = .init(width: frame.size.width - padding * 2,
                          height: min(rowHeight, frame.size.height - padding * 2))
        displaySize = .init(width: worldSize.width * scale, height: worldSize.height * scale)
        displayOrigin = .init(x: padding * scale, y: padding * scale)
        guard displaySize.width.isFinite, displaySize.height.isFinite,
              displayOrigin.x.isFinite, displayOrigin.y.isFinite else { return nil }
    }
}

/// A visitor page fits available width, never its full document height.
/// Tall pages scroll instead of shrinking native links/menus into unusable
/// thumbnails. This is presentation only; authored bounds stay unchanged.
struct CanvasPreviewPresentationGeometry: Equatable, Sendable {
    let scale: Double
    let contentSize: WorldSize
    static let inset = 28.0

    init?(bounds: WorldRect, available: WorldSize) {
        guard [bounds.size.width, bounds.size.height, available.width, available.height]
            .allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        scale = min(1, max(1, available.width - Self.inset * 2) / bounds.size.width)
        contentSize = .init(width: max(available.width, bounds.size.width * scale + Self.inset * 2),
                            height: max(available.height, bounds.size.height * scale + Self.inset * 2))
    }
}

struct CanvasPreviewSceneSnapshot: Equatable, Sendable {
    let documentID: DocumentID
    let revision: UInt64
    let objects: [CanvasRenderObject]
    let deterministicDigest: String
    var pageBackground: CanvasRenderObject? = nil
}

/// A native accessibility owner follows canonical ancestry, never rectangle
/// overlap. World frames remain unchanged; the view only subtracts the owner
/// origin when positioning its existing child views.
struct CanvasPreviewPresentationGroup: Identifiable, Equatable, Sendable {
    let id: NodeID
    let container: CanvasRenderObject?
    let objects: [CanvasRenderObject]

    static func resolve(_ source: [CanvasRenderObject]) -> [Self] {
        let objects = source.filter { $0.isVisible && $0.navigationOwnerID == nil }
            .sorted { $0.paintOrder == $1.paintOrder ? $0.id.description < $1.id.description : $0.paintOrder < $1.paintOrder }
        var byID: [NodeID: CanvasRenderObject] = [:]
        for object in source where byID[object.id] == nil { byID[object.id] = object }
        var owners: [NodeID: NodeID] = [:], resolved = Set<NodeID>()
        for object in objects {
            var path: [NodeID] = [], visited = Set<NodeID>(), cursor: NodeID? = object.id
            var owner: NodeID?
            while let id = cursor, visited.insert(id).inserted, let node = byID[id] {
                if resolved.contains(id) { owner = owners[id]; break }
                path.append(id)
                if node.pageFlowRole == .header || node.pageFlowRole == .footer { owner = id; break }
                cursor = node.parentNodeID
            }
            for id in path { resolved.insert(id); owners[id] = owner }
        }
        var members: [NodeID: [CanvasRenderObject]] = [:], order: [NodeID] = []
        for object in objects {
            let id = owners[object.id] ?? object.id
            if members[id] == nil { order.append(id) }
            members[id, default: []].append(object)
        }
        return order.compactMap { id in
            guard let items = members[id], let first = byID[id] else { return nil }
            let container = first.pageFlowRole == .header || first.pageFlowRole == .footer ? first : nil
            return .init(id: id, container: container, objects: items)
        }
    }
}

struct LocalPreviewPageSnapshot: Equatable, Sendable, Identifiable {
    let id: PageID
    let name: String
    let route: PageRoute
    let role: PageRole
    let viewportBounds: WorldRect
    let objects: [CanvasRenderObject]
    var pageBackground: CanvasRenderObject? = nil
}

/// An immutable, document-revision-owned Preview bundle. Navigation mutates
/// only `LocalPreviewState`; no active editor page, selection, history, or
/// canonical document value is changed by visitor actions.
struct LocalPreviewRuntimeSnapshot: Equatable, Sendable {
    let documentID: DocumentID
    let revision: UInt64
    let pages: [LocalPreviewPageSnapshot]
    let deterministicDigest: String
}

// SF-1202 v1: immutable internal render-tree metadata. This compiler consumes
// an already-adopted scene; it cannot write canonical content or UI state.
struct InternalRenderTreeNode: Equatable, Sendable {
    let id: NodeID
    let sourceNodeID: NodeID
    /// Canonical parent identity is immutable output provenance. It is not a
    /// browser DOM mutation or an editor-side hierarchy cache.
    let parentNodeID: NodeID?
    let paintOrder: Int
    let frame: WorldRect
    let semanticElement: String
    let cssSelector: String
    let formField: InternalFormField?
    let control: InternalStaticControl?
    let anchorID: String?
    /// Only canonical plain text enters this static projection. The emitter
    /// escapes it at the final HTML-context boundary.
    let textContent: String?
    let isManagedChromeTitle: Bool
    /// Canonical typography intent is immutable metadata here; output maps
    /// only its closed allowlist and never consults installed fonts.
    let typography: CanonicalTypography?
    let textForeground: CanonicalSolidColor?
    /// Image resource intent is canonical and path-independent. A verified
    /// content-addressed output path is optional because planning must retain
    /// a missing resource reference without manufacturing a URL.
    let image: InternalStaticImage?
    let imageFill: InternalStaticImage?
    /// Closed canonical fill layers are immutable render metadata. They are
    /// present only for the supported static-output node kinds.
    let fillLayers: [CanonicalFillLayer]
    let opacity: Double?
    /// Closed box appearance reaches static output only through this typed
    /// immutable projection; no presentation string becomes CSS input.
    let boxStyle: CanonicalBoxStyle?
    /// Base-only fixed sizing metadata. Static output uses only closed,
    /// validated declarations; responsive constraint overrides are absent.
    let sizingConstraints: CanonicalSizingConstraints?
    /// Closed positioning and resolved appearances are immutable projections
    /// of canonical data. They never carry raw selectors or presentation CSS.
    let positioning: CanonicalPositioning?
    let resolvedAppearance: CanonicalResolvedAppearance?
    let interactionAppearances: [CanonicalInteractionStyleState: CanonicalResolvedAppearance]
    let accessibilityName: String?
    let accessibilityHelp: String?
    let pageFlowRole: PageFlowRole?
    let navigation: InternalStaticNavigation?
    let navigationOwnerID: NodeID?
    let usesConnectedLayout: Bool

    init(id: NodeID, sourceNodeID: NodeID, parentNodeID: NodeID? = nil, paintOrder: Int, frame: WorldRect,
         semanticElement: String, cssSelector: String, formField: InternalFormField?,
         control: InternalStaticControl? = nil, anchorID: String? = nil,
         textContent: String? = nil, typography: CanonicalTypography? = nil,
         isManagedChromeTitle: Bool = false,
         textForeground: CanonicalSolidColor? = nil,
         image: InternalStaticImage? = nil, imageFill: InternalStaticImage? = nil,
         fillLayers: [CanonicalFillLayer] = [],
         opacity: Double? = nil, boxStyle: CanonicalBoxStyle? = nil,
         sizingConstraints: CanonicalSizingConstraints? = nil,
         positioning: CanonicalPositioning? = nil,
         resolvedAppearance: CanonicalResolvedAppearance? = nil,
         interactionAppearances: [CanonicalInteractionStyleState: CanonicalResolvedAppearance] = [:],
         accessibilityName: String? = nil, accessibilityHelp: String? = nil,
         pageFlowRole: PageFlowRole? = nil, navigation: InternalStaticNavigation? = nil, navigationOwnerID: NodeID? = nil,
         usesConnectedLayout: Bool = false) {
        self.id = id
        self.sourceNodeID = sourceNodeID
        self.parentNodeID = parentNodeID
        self.paintOrder = paintOrder
        self.frame = frame
        self.semanticElement = semanticElement
        self.cssSelector = cssSelector
        self.formField = formField
        self.control = control
        self.anchorID = anchorID
        self.textContent = textContent
        self.isManagedChromeTitle = isManagedChromeTitle
        self.typography = typography
        self.textForeground = textForeground
        self.image = image
        self.imageFill = imageFill
        self.fillLayers = fillLayers
        self.opacity = opacity
        self.boxStyle = boxStyle
        self.sizingConstraints = sizingConstraints
        self.positioning = positioning
        self.resolvedAppearance = resolvedAppearance
        self.interactionAppearances = interactionAppearances
        self.accessibilityName = accessibilityName
        self.accessibilityHelp = accessibilityHelp
        self.pageFlowRole = pageFlowRole
        self.navigation = navigation
        self.navigationOwnerID = navigationOwnerID
        self.usesConnectedLayout = usesConnectedLayout
    }
}

/// Immutable, render-only control projection. It contains only a validated
/// static route; untargeted buttons have no browser runtime behavior.
struct InternalStaticNavigation: Equatable, Sendable {
    struct Link: Equatable, Sendable { let id: NodeID; let label: String; let href: String?; var isCurrentPage = false; var opensNewContext = false }
    let links: [Link]
    let hamburgerEnabled: Bool
    var role: PageFlowRole? = nil
}

struct InternalStaticControl: Equatable, Sendable {
    let label: String
    let href: String?
    let isLink: Bool
    /// A canonical `.new` context becomes only the safe static HTML pair
    /// below; it never creates an editor-side browser or navigation runtime.
    let opensNewContext: Bool
    let disabled: Bool
}

/// A safe static Image projection. `outputPath` can only originate from the
/// verified content-addressed asset planner; it is never a Finder path or a
/// user-authored URL.
struct InternalStaticImage: Equatable, Sendable {
    let assetID: AssetID
    let outputPath: String?
    /// Verified resource metadata is a sizing hint only. Canonical layout and
    /// responsive overrides remain the sole source for the authored box.
    let intrinsicWidth: Int?
    let intrinsicHeight: Int?
    let altText: String
    let isDecorative: Bool
    let fitMode: ImageFitMode
    let focalX: Double
    let focalY: Double
}

struct InternalFormField: Equatable, Sendable {
    let kind: String
    let label: String
    let name: String
    let help: String?
    let required: Bool
    let formID: NodeID
    let options: [InternalFormOption]
    let maximumLength: Int?

    init(kind: String, label: String, name: String, help: String?, required: Bool,
         formID: NodeID, options: [InternalFormOption], maximumLength: Int? = nil) {
        self.kind = kind; self.label = label; self.name = name; self.help = help
        self.required = required; self.formID = formID; self.options = options
        self.maximumLength = maximumLength
    }
}

/// Render-only projection of a canonical select option. The option identity is
/// never derived from a display label, so reordering and renaming remain safe.
struct InternalFormOption: Equatable, Sendable {
    let id: FormOptionID
    let label: String
    let value: String
}

struct InternalRenderTreeSnapshot: Equatable, Sendable {
    let documentID: DocumentID
    let revision: UInt64
    let pageID: PageID?
    let nodes: [InternalRenderTreeNode]

    init(documentID: DocumentID, revision: UInt64, pageID: PageID? = nil, nodes: [InternalRenderTreeNode]) {
        self.documentID = documentID
        self.revision = revision
        self.pageID = pageID
        self.nodes = nodes
    }
}

enum InternalRenderTreeCompiler {
    static func compile(_ scene: CanvasPreviewSceneSnapshot) -> InternalRenderTreeSnapshot {
        let nodes = scene.objects.filter(\.isVisible).sorted { $0.paintOrder < $1.paintOrder }.map { object in
            InternalRenderTreeNode(
                id: object.id, sourceNodeID: object.id, paintOrder: object.paintOrder, frame: object.frame,
                semanticElement: object.semanticElement ?? "div",
                cssSelector: CanonicalCSSRule.selector(for: object.id), formField: nil
            )
        }
        return .init(documentID: scene.documentID, revision: scene.revision, nodes: nodes)
    }
}

/// The static build path starts from validated canonical document state rather
/// than a live canvas scene. It projects only typed form metadata; visitor
/// values and submission destinations never enter the build snapshot.
enum InternalDocumentRenderTreeCompiler {
    static func compile(
        page: DocumentPage,
        documentID: DocumentID,
        revision: UInt64,
        staticRoutes: [PageID: String] = [:],
        sectionIDs: [PageID: Set<NodeID>] = [:],
        imageOutputPaths: [AssetID: String] = [:],
        imageAssets: [AssetID: ImageAsset] = [:],
        colorTokens: [LocalColorToken] = [],
        reusableStyleIndex: CanonicalReusableStyleIndex? = nil,
        breakpoint: ResponsiveBreakpoint = .desktop,
        viewportWidth: Double? = nil
    ) throws -> InternalRenderTreeSnapshot {
        guard Set(page.nodes.map(\.id)).count == page.nodes.count else { throw SafeHTMLEmissionError.invalidIdentity }
        let nodesByID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let connected = page.usesConnectedOutput
        let managedTitleIDs = Set(page.nodes.compactMap { owner -> NodeID? in
            guard [.header, .footer].contains(CanonicalPageFlow.role(owner)) else { return nil }
            return CanonicalPageChrome.reference(CanonicalPageChrome.titleKey, on: owner)
        })
        let navigationSurfaces = Set(page.nodes.compactMap { owner -> NodeID? in
            guard [.header, .footer].contains(CanonicalPageFlow.role(owner)) else { return nil }
            return CanonicalPageChrome.reference(CanonicalPageChrome.navigationKey, on: owner) ?? owner.id
        })
        let geometry = page.resolvedStructuralGeometry(breakpoint: breakpoint,
            viewportWidth: CanonicalPageFlow.pageWidth(breakpoint, viewportWidth),
            availablePageIDs: Set(staticRoutes.keys))
        let nodes = try page.canonicalDepthFirstNodes().enumerated().map { paintOrder, node in
            let formField = try field(for: node, nodesByID: nodesByID)
            let control = try control(for: node, staticRoutes: staticRoutes, sectionIDs: sectionIDs)
            let baseAppearance = try reusableStyleIndex.map {
                try CanonicalResolvedAppearance.resolve(node: node, index: $0)
            }
            var stateAppearances: [CanonicalInteractionStyleState: CanonicalResolvedAppearance] = [:]
            if let reusableStyleIndex {
                for state in CanonicalInteractionStyleState.allCases where state != .default {
                    let prefix = CanonicalReusableStyleIndex.stateNamespace + state.rawValue + "."
                    guard node.insertionProperty(prefix + "id") != nil else { continue }
                    stateAppearances[state] = try CanonicalResolvedAppearance.resolve(
                        node: node, index: reusableStyleIndex, state: state)
                }
            }
            return InternalRenderTreeNode(
                id: node.id, sourceNodeID: node.id,
                parentNodeID: { if case .node(let parent) = node.parent { parent } else { nil } }(),
                paintOrder: paintOrder,
                frame: connected ? (geometry[node.id]?.frame ?? .init(origin: .init(x: 0, y: 0), size: .init(width: 0, height: 0)))
                    : .init(origin: .init(x: 0, y: 0), size: .init(width: 0, height: 0)),
                semanticElement: CanonicalSemanticElement.resolved(for: node)?.0.rawValue ?? "div",
                cssSelector: CanonicalCSSRule.selector(for: node.id), formField: formField,
                control: control,
                anchorID: sectionIDs[page.id]?.contains(node.id) == true ? anchorID(for: node.id) : nil,
                textContent: node.kind == .text ? node.insertionStringProperty("content.text") : nil,
                typography: node.kind.isTextual ? CanonicalTypography.resolved(for: node) : nil,
                isManagedChromeTitle: managedTitleIDs.contains(node.id) && node.kind == .text,
                textForeground: LocalColorTokenResolver.textForeground(for: node, tokens: colorTokens),
                image: staticImage(for: node, outputPaths: imageOutputPaths, assets: imageAssets),
                imageFill: staticImageFill(for: node, outputPaths: imageOutputPaths),
                fillLayers: staticFillLayers(for: node, colorTokens: colorTokens),
                opacity: staticOpacity(for: node),
                boxStyle: staticBoxStyle(for: node, colorTokens: colorTokens),
                sizingConstraints: CanonicalSizingConstraints.supportedKinds.contains(node.kind)
                    ? CanonicalSizingConstraints.resolved(for: node) : nil,
                positioning: CanonicalPositioning.resolve(node),
                resolvedAppearance: baseAppearance,
                interactionAppearances: stateAppearances,
                accessibilityName: CanonicalAccessibilityMetadata.value(.name, for: node).0,
                accessibilityHelp: CanonicalAccessibilityMetadata.value(.help, for: node).0,
                pageFlowRole: CanonicalPageFlow.role(node),
                navigation: navigationSurfaces.contains(node.id)
                    ? staticNavigation(owner: node, page: page, staticRoutes: staticRoutes, sectionIDs: sectionIDs) : nil,
                navigationOwnerID: CanonicalPageFlow.isNavigationLink(node) ? { if case .node(let id) = node.parent { id } else { nil } }() : nil,
                usesConnectedLayout: connected
            )
        }
        return .init(documentID: documentID, revision: revision, pageID: page.id, nodes: nodes)
    }

    private static func staticNavigation(owner: DocumentNode, page: DocumentPage,
                                         staticRoutes: [PageID: String], sectionIDs: [PageID: Set<NodeID>]) -> InternalStaticNavigation? {
        guard CanonicalPageFlow.role(owner) != nil || owner.kind == .stack,
              let settings = CanonicalPageChrome.navigationSettings(for: owner, page: page) else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let links = owner.childIDs.compactMap { id -> InternalStaticNavigation.Link? in
            guard let node = byID[id], !node.selectionBooleanProperty("hidden"), CanonicalPageFlow.isNavigationLink(node),
                  let control = try? Self.control(for: node, staticRoutes: staticRoutes, sectionIDs: sectionIDs) else { return nil }
            let current: Bool = { if let target = try? CanonicalLinkTarget.resolve(node), case .page(let id) = target { id == page.id } else { false } }()
            return .init(id: node.id, label: node.controlLabel, href: control.href, isCurrentPage: current, opensNewContext: control.opensNewContext)
        }
        guard !links.isEmpty else { return nil }
        return .init(links: links, hamburgerEnabled: settings.insertionProperty(CanonicalPageFlow.hamburgerKey)?.value == .boolean(true),
                     role: CanonicalPageFlow.role(settings))
    }

    private static func staticImage(
        for node: DocumentNode,
        outputPaths: [AssetID: String],
        assets: [AssetID: ImageAsset]
    ) -> InternalStaticImage? {
        guard let style = CanonicalImageStyle.resolve(node) else { return nil }
        let asset = assets[style.assetID]
        let hasSafeDimensions = asset.map {
            (1...ImageAsset.maximumPixelDimension).contains($0.pixelWidth) &&
            (1...ImageAsset.maximumPixelDimension).contains($0.pixelHeight)
        } == true
        return .init(
            assetID: style.assetID,
            outputPath: outputPaths[style.assetID],
            intrinsicWidth: hasSafeDimensions ? asset?.pixelWidth : nil,
            intrinsicHeight: hasSafeDimensions ? asset?.pixelHeight : nil,
            altText: style.altText,
            isDecorative: style.isDecorative,
            fitMode: style.fitMode,
            focalX: style.focalX,
            focalY: style.focalY
        )
    }

    private static func staticImageFill(for node: DocumentNode,
                                        outputPaths: [AssetID: String]) -> InternalStaticImage? {
        guard let fill = CanonicalImageFill.resolve(node) else { return nil }
        return .init(assetID: fill.assetID, outputPath: outputPaths[fill.assetID],
                     intrinsicWidth: nil, intrinsicHeight: nil, altText: "",
                     isDecorative: true, fitMode: fill.mode, focalX: 0.5, focalY: 0.5)
    }

    /// The SF-AUTHORING-054 output subset deliberately limits style emission
    /// to Frame and Section. The renderer remains authoritative for the wider
    /// editor-supported layer model until those node kinds have explicit
    /// static-output acceptance.
    private static func staticFillLayers(for node: DocumentNode, colorTokens: [LocalColorToken]) -> [CanonicalFillLayer] {
        guard [.frame, .section].contains(node.kind) else { return [] }
        return LocalColorTokenResolver.resolvedLayers(for: node, tokens: colorTokens)
    }

    private static func staticOpacity(for node: DocumentNode) -> Double? {
        guard DesignBoxStyleCommandRegistry.applicableKinds.contains(node.kind),
              let value = node.insertionNumberProperty("style.opacity"),
              value.isFinite, (0...1).contains(value) else { return nil }
        return value
    }

    private static func staticBoxStyle(for node: DocumentNode,
                                       colorTokens: [LocalColorToken]) -> CanonicalBoxStyle? {
        guard DesignBoxStyleCommandRegistry.applicableKinds.contains(node.kind),
              DesignBoxStyleCommandRegistry.hasWellFormedContentBoxProperties(node) else { return nil }
        return LocalColorTokenResolver.resolvedBoxStyle(for: node, tokens: colorTokens)
    }

    /// SF-0806/SF-1102/SF-1203 v1: resolve only typed, prevalidated targets
    /// into static routes. A missing internal target remains an accessible,
    /// inert control instead of becoming a permissive raw URL or script path.
    private static func control(
        for node: DocumentNode,
        staticRoutes: [PageID: String],
        sectionIDs: [PageID: Set<NodeID>]
    ) throws -> InternalStaticControl? {
        guard node.kind.isLinkControl else { return nil }
        do {
            try CanonicalLinkTarget.validate(node)
        } catch {
            throw SafeHTMLEmissionError.invalidControl
        }
        let target = try CanonicalLinkTarget.resolve(node)
        let href: String?
        switch target {
        case .none:
            href = nil
        case .external(let url):
            href = url
        case .page(let pageID):
            href = staticRoutes[pageID]
        case .section(let pageID, let nodeID):
            guard let route = staticRoutes[pageID], sectionIDs[pageID]?.contains(nodeID) == true else {
                href = nil
                break
            }
            href = route + "#" + anchorID(for: nodeID)
        }
        // A typed navigation destination is a native anchor even when its
        // authored appearance is Button. Untargeted actions remain inert;
        // this does not introduce scripting or form submission behavior.
        let isLink = node.kind == .link || target != .none
        return .init(
            label: node.controlLabel,
            href: isLink ? href : nil,
            isLink: isLink,
            opensNewContext: isLink && href != nil && node.controlContext == .new,
            disabled: !isLink || href == nil
        )
    }

    private static func anchorID(for nodeID: NodeID) -> String {
        "sf-node-" + nodeID.rawValue.uuidString.lowercased()
    }

    private static func field(for node: DocumentNode, nodesByID: [NodeID: DocumentNode]) throws -> InternalFormField? {
        guard node.properties.contains(where: { $0.key.rawValue.hasPrefix("form.field.v1.") }) else { return nil }
        // The compiler can be called independently of package decode. Reuse
        // the canonical validator so malformed field state never becomes
        // permissive static output through this second boundary.
        do {
            try CanonicalFormFieldValidator.validate(node)
        } catch {
            throw SafeHTMLEmissionError.invalidFormField
        }
        guard case .node(let formID) = node.parent, nodesByID[formID]?.kind == .form,
              let kind = node.insertionStringProperty(CanonicalFormField.kindKey),
              let label = node.insertionStringProperty(CanonicalFormField.labelKey),
              let name = node.insertionStringProperty(CanonicalFormField.nameKey),
              let requiredProperty = node.insertionProperty(CanonicalFormField.requiredKey),
              case .boolean(let required) = requiredProperty.value else {
            throw SafeHTMLEmissionError.invalidFormField
        }
        let options: [InternalFormOption]
        if kind == "select" {
            guard let encoded = node.insertionStringProperty(CanonicalFormField.optionsKey) else {
                throw SafeHTMLEmissionError.invalidFormField
            }
            options = try CanonicalFormSelectOptions.decode(encoded).map {
                .init(id: $0.id, label: $0.label, value: $0.value)
            }
        } else {
            options = []
        }
        return .init(kind: kind, label: label, name: name,
                     help: node.insertionStringProperty(CanonicalFormField.helpKey),
                     required: required, formID: formID, options: options,
                     maximumLength: node.insertionNumberProperty(CanonicalFormField.maximumLengthKey).map { Int($0) })
    }
}

// SF-1204 v1 emits only fixed layout declarations derived from typed geometry.
// It is pure/in-memory; authored text cannot enter this syntax surface.
enum SafeCSSEmissionError: Error, Equatable, Sendable { case invalidGeometry, invalidIdentity }

enum SafeCSSEmitter {
    static func emit(_ tree: InternalRenderTreeSnapshot) throws -> String {
        let geometry = try tree.nodes.sorted { $0.paintOrder < $1.paintOrder }.map { node in
            let f = node.frame
            guard [f.origin.x, f.origin.y, f.size.width, f.size.height].allSatisfy(\.isFinite),
                  f.size.width >= 0, f.size.height >= 0 else { throw SafeCSSEmissionError.invalidGeometry }
            let id = node.id.rawValue.uuidString.lowercased()
            guard id == node.sourceNodeID.rawValue.uuidString.lowercased() else { throw SafeCSSEmissionError.invalidIdentity }
            var declarations = "height: \(f.size.height)px; left: \(f.origin.x)px; position: absolute; top: \(f.origin.y)px; width: \(f.size.width)px;"
            if let sizing = node.sizingConstraints {
                guard sizing.isValid else { throw SafeCSSEmissionError.invalidGeometry }
                for (name, value) in [("min-width", sizing.minWidth), ("min-height", sizing.minHeight),
                                      ("max-width", sizing.maxWidth), ("max-height", sizing.maxHeight)] {
                    if let value { declarations += " \(name): \(value)px;" }
                }
                if sizing.aspectEnabled, let ratio = sizing.aspectRatio {
                    declarations += " aspect-ratio: \(ratio);"
                }
            }
            return "[data-siteforge-node=\"\(id)\"] { \(declarations) }"
        }.joined(separator: "\n")
        // Fixed output-only control baseline. It neither exposes authored
        // values nor creates a submission path; per-control styling remains
        // deferred until a typed Form-style model exists.
        let controls = tree.nodes.contains { $0.formField != nil } ? "form { font: inherit; } form input, form select, form textarea, form button { box-sizing: border-box; font: inherit; max-width: 100%; } form button[disabled] { cursor: not-allowed; }" : ""
        return [geometry, controls].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

/// Static typography is an immutable projection of the closed canonical
/// plain-text model. It deliberately omits arbitrary installed-family names:
/// only the canonical System default becomes the portable `system-ui` family.
/// The remaining declarations are finite, allowlisted scalars/enums.
enum StaticTypographyOutputEmitter {
    static func emit(nodes: [InternalRenderTreeNode]) -> String {
        nodes.filter { $0.typography != nil }
            .sorted { $0.id.description < $1.id.description }
            .compactMap(rule(for:))
            .joined(separator: "\n")
    }

    private static func rule(for node: InternalRenderTreeNode) -> String? {
        guard node.id == node.sourceNodeID,
              node.cssSelector == CanonicalCSSRule.selector(for: node.id),
              let style = node.typography else { return nil }
        var declarations = [
            "font-size: \(number(style.size))px;",
            "font-weight: \(weight(style.weight));",
            "letter-spacing: \(number(style.tracking))px;",
            "line-height: \(number(style.lineHeight))px;",
            "text-align: \(alignment(style.alignment));",
            "white-space: pre-wrap;",
        ]
        if node.isManagedChromeTitle {
            declarations.append("--sf-text-height: \(number(node.frame.size.height))px;")
        }
        if style.family == CanonicalTypography.defaultFamily {
            declarations.insert("font-family: system-ui;", at: 0)
        } else {
            // Font intent remains text, never CSS syntax or a remote font URL.
            // The same installed family is available to AppKit and Safari;
            // unavailable names fall back to the shared system-family policy.
            let family = style.family.unicodeScalars.map { scalar -> String in
                if CharacterSet.alphanumerics.contains(scalar) || scalar == " " || scalar == "-" {
                    return String(scalar)
                }
                return "\\" + String(scalar.value, radix: 16) + " "
            }.joined()
            declarations.insert("font-family: \"\(family)\", system-ui;", at: 0)
        }
        if let color = node.textForeground {
            declarations.append("color: rgba(\(number(color.red * 255)), \(number(color.green * 255)), \(number(color.blue * 255)), \(number(color.alpha)));")
        }
        let selector = CanonicalCSSRule.selector(for: node.id)
        // Managed navigation renders inline/menu copies with stable link
        // identity, not the ordinary node attribute (which would also apply
        // absolute authored geometry). Both copies still own this typography.
        let typographySelector = node.navigationOwnerID == nil ? selector
            : "\(selector), [data-siteforge-nav-link=\"\(node.id)\"]"
        let typography = "\(typographySelector) { \(declarations.joined(separator: " ")) }"
        if node.control == nil {
            guard node.textContent != nil, node.formField == nil else { return typography }
            if node.isManagedChromeTitle {
                // Keep the semantic node and complete accessible text. A neutral
                // inline box owns truncation, while the authored box continues
                // centering the whole visible block. `1lh` tracks fluid type;
                // connected geometry supplies the live breakpoint height.
                return typography + "\n\(selector)[data-siteforge-node] { display:flex;flex-direction:column;justify-content:center;overflow:hidden; }"
                    + "\n\(selector) > [data-siteforge-text] { box-sizing:border-box;width:100%;padding-inline:\(number(CanvasTextLayoutPolicy.horizontalInset))px;flex:none;display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:max(1,round(down,calc(var(--sf-text-height) / 1lh),1));overflow:hidden; }"
            }
            // CanvasTextLayout centers the whole line-fragment block in its
            // authored frame. Preserve that contract without moving canonical
            // geometry; Form controls keep their own label/input layout.
            return typography + "\n\(selector)[data-siteforge-node] { display:flex;flex-direction:column;justify-content:center;overflow:hidden; }"
        }
        let horizontal = switch style.alignment {
        case .leading: "flex-start"
        case .center: "center"
        case .trailing: "flex-end"
        }
        // Native control bezels/underlines are not authored appearance. Keep
        // their reset separate from typography so fluid font rules still win.
        return typography + "\n\(selector):is(a,button) { display:flex;align-items:center;justify-content:\(horizontal);border:0;text-decoration:none; }"
    }

    private static func weight(_ value: CanonicalFontWeight) -> Int {
        switch value {
        case .regular: 400
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        }
    }

    private static func alignment(_ value: CanonicalTextAlignment) -> String {
        switch value {
        case .leading: "left"
        case .center: "center"
        case .trailing: "right"
        }
    }

    private static func number(_ value: Double) -> String {
        let rounded = (value * 1_000).rounded() / 1_000
        var output = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        while output.contains(".") && output.last == "0" { output.removeLast() }
        if output.last == "." { output.append("0") }
        return output == "-0.0" ? "0.0" : output
    }
}

/// Static image presentation maps only the closed canonical fit/focal model to
/// fixed CSS. It does not create a crop, rendition, transform, or image-edit
/// surface; the original verified resource reference remains unchanged.
enum StaticImageStyleOutputEmitter {
    static func emit(nodes: [InternalRenderTreeNode]) -> String {
        nodes.filter { $0.image != nil }
            .sorted { $0.id.description < $1.id.description }
            .compactMap(rule(for:))
            .joined(separator: "\n")
    }

    private static func rule(for node: InternalRenderTreeNode) -> String? {
        guard node.id == node.sourceNodeID,
              node.cssSelector == CanonicalCSSRule.selector(for: node.id),
              let image = node.image,
              image.focalX.isFinite, image.focalY.isFinite,
              (0...1).contains(image.focalX), (0...1).contains(image.focalY) else {
            return nil
        }
        let fit: String = switch image.fitMode {
        case .fit: "contain"
        case .fill: "cover"
        case .stretch: "fill"
        }
        let focal = "\(number(image.focalX * 100))% \(number(image.focalY * 100))%"
        return "\(node.cssSelector) { object-fit: \(fit); object-position: \(focal); }"
    }

    private static func number(_ value: Double) -> String {
        let rounded = (value * 1_000).rounded() / 1_000
        var output = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        while output.contains(".") && output.last == "0" { output.removeLast() }
        if output.last == "." { output.append("0") }
        return output == "-0.0" ? "0.0" : output
    }
}

/// SF-0504/SF-0510/SF-0511 static projection. Only the closed canonical
/// positioning vocabulary and the four approved interaction pseudo-classes
/// can cross this boundary. Reusable-style names and raw authored strings are
/// deliberately absent from emitted output.
enum StaticAdvancedStyleOutputEmitter {
    static func emit(nodes: [InternalRenderTreeNode]) -> String {
        nodes.sorted { $0.id.description < $1.id.description }
            .flatMap(rules(for:))
            .joined(separator: "\n")
    }

    private static func rules(for node: InternalRenderTreeNode) -> [String] {
        guard node.id == node.sourceNodeID,
              node.cssSelector == CanonicalCSSRule.selector(for: node.id) else { return [] }
        var output: [String] = []
        if let positioning = node.positioning {
            var declarations = ["position: \(positioning.mode.rawValue);"]
            for (name, value) in [
                ("top", positioning.top), ("right", positioning.right),
                ("bottom", positioning.bottom), ("left", positioning.left),
            ] where value != nil {
                declarations.append("\(name): \(number(value!))px;")
            }
            if positioning.zIndex != 0 { declarations.append("z-index: \(positioning.zIndex);") }
            output.append("\(node.cssSelector) { \(declarations.joined(separator: " ")) }")
        }
        if let appearance = node.resolvedAppearance {
            let includeFill = node.fillLayers.isEmpty && appearance.fill != nil
            let includeOpacity = node.opacity == nil && appearance.opacity != 1
            if includeFill || includeOpacity {
                let resolvedDeclarations = declarations(
                    for: appearance,
                    includeFill: includeFill,
                    includeOpacity: includeOpacity
                )
                output.append("\(node.cssSelector) { \(resolvedDeclarations) }")
            }
        }
        for state in CanonicalInteractionStyleState.allCases where state != .default {
            guard let appearance = node.interactionAppearances[state],
                  let pseudoClass = pseudoClass(for: state) else { continue }
            output.append("\(node.cssSelector)\(pseudoClass) { \(declarations(for: appearance)) }")
        }
        return output
    }

    private static func declarations(
        for appearance: CanonicalResolvedAppearance,
        includeFill: Bool = true,
        includeOpacity: Bool = true
    ) -> String {
        var values: [String] = []
        if includeFill, let color = appearance.fill {
            values.append("background-color: rgba(\(number(color.red * 255)), \(number(color.green * 255)), \(number(color.blue * 255)), \(number(color.alpha)));")
        }
        if includeOpacity { values.append("opacity: \(number(appearance.opacity));") }
        return values.joined(separator: " ")
    }

    private static func pseudoClass(for state: CanonicalInteractionStyleState) -> String? {
        switch state {
        case .default: nil
        case .hover: ":hover"
        case .focus: ":focus-visible"
        case .pressed: ":active"
        case .disabled: ":disabled"
        }
    }

    private static func number(_ value: Double) -> String {
        let rounded = (value * 1_000).rounded() / 1_000
        var output = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        while output.contains(".") && output.last == "0" { output.removeLast() }
        if output.last == "." { output.append("0") }
        return output == "-0.0" ? "0.0" : output
    }
}

/// SF-0508/SF-0701 bounded static-output adoption. This emitter maps only the
/// closed canonical Frame/Section fill-layer model into fixed declarations;
/// it accepts neither raw CSS nor a browser-side gradient description.
enum StaticFillLayerStyleOutputEmitter {
    static func emit(nodes: [InternalRenderTreeNode]) -> String {
        nodes.sorted { $0.id.description < $1.id.description }
            .compactMap(rule(for:))
            .joined(separator: "\n")
    }

    private static func rule(for node: InternalRenderTreeNode) -> String? {
        guard node.id == node.sourceNodeID,
              node.cssSelector == CanonicalCSSRule.selector(for: node.id) else { return nil }
        let enabled = node.fillLayers.filter(\.isEnabled)
        guard enabled.allSatisfy(\.isValid) else { return nil }
        var declarations: [String] = []
        if !enabled.isEmpty || node.imageFill != nil {
            var images = enabled.reversed().compactMap(gradientImage(for:))
            guard images.count == enabled.count else { return nil }
            if let fill = node.imageFill {
                if let path = fill.outputPath,
                   path.range(of: "^assets/[a-f0-9]{64}\\.(png|jpg)$", options: .regularExpression) != nil {
                    images.insert("url(\"\(path)\")", at: 0)
                    declarations.append("background-size: \(fill.fitMode == .fit ? "contain" : "cover");")
                    declarations.append("background-position: center;")
                    declarations.append("background-repeat: no-repeat;")
                } else if images.isEmpty {
                    declarations.append("background-image: none; /* Missing local image fill */")
                }
            }
            if !images.isEmpty { declarations.append("background-image: \(images.joined(separator: ", "));" ) }
        }
        if let opacity = node.opacity {
            declarations.append("opacity: \(number(opacity));")
        }
        guard !declarations.isEmpty else { return nil }
        return "\(node.cssSelector) { \(declarations.joined(separator: " ")) }"
    }

    private static func gradientImage(for layer: CanonicalFillLayer) -> String? {
        switch layer.kind {
        case .solid:
            guard let color = layer.solidColor else { return nil }
            let rgba = cssRGBA(color)
            return "linear-gradient(90deg, \(rgba) 0%, \(rgba) 100%)"
        case .linearGradient:
            guard let angle = layer.normalizedAngleDegrees else { return nil }
            let cssAngle = (90 + angle).truncatingRemainder(dividingBy: 360)
            let stops = layer.stops.enumerated().sorted {
                $0.element.position == $1.element.position ? $0.offset < $1.offset : $0.element.position < $1.element.position
            }.map { "\(cssRGBA($0.element.color)) \(number($0.element.position * 100))%" }
            guard stops.count >= 2 else { return nil }
            return "linear-gradient(\(number(cssAngle))deg, \(stops.joined(separator: ", ")))"
        }
    }

    private static func cssRGBA(_ color: CanonicalSolidColor) -> String {
        "rgba(\(number(color.red * 255)), \(number(color.green * 255)), \(number(color.blue * 255)), \(number(color.alpha)))"
    }

    private static func number(_ value: Double) -> String {
        let rounded = (value * 1_000).rounded() / 1_000
        var output = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        while output.contains(".") && output.last == "0" { output.removeLast() }
        if output.last == "." { output.append("0") }
        return output == "-0.0" ? "0.0" : output
    }
}

/// SF-0506/SF-1204 bounded output projection. The declaration vocabulary is
/// closed and values originate exclusively in the typed Frame/Section model.
enum StaticBoxStyleOutputEmitter {
    static func emit(nodes: [InternalRenderTreeNode]) -> String {
        nodes.sorted { $0.id.description < $1.id.description }.compactMap { node in
            guard node.id == node.sourceNodeID,
                  node.cssSelector == CanonicalCSSRule.selector(for: node.id),
                  let style = node.boxStyle, style.isValid else { return nil }
            var declarations: [String] = []
            if let border = style.border {
                if node.usesConnectedLayout {
                    declarations.append("border:0; outline: \(number(border.width))px \(border.style.rawValue) \(rgba(border.color)); outline-offset:-\(number(border.width))px;")
                } else {
                    declarations.append("border: \(number(border.width))px \(border.style.rawValue) \(rgba(border.color));")
                }
            }
            if let radius = style.cornerRadius { declarations.append("border-radius: \(number(radius))px;") }
            if let padding = style.padding, !node.usesConnectedLayout { declarations.append("padding: \(number(padding))px;") }
            if style.clipsContent == true { declarations.append("overflow: hidden;") }
            if let shadow = style.shadow, style.shadowEnabled != false {
                declarations.append("box-shadow: \(number(shadow.offsetX))px \(number(shadow.offsetY))px \(number(shadow.blur))px \(number(shadow.spread))px \(rgba(shadow.color));")
            }
            guard !declarations.isEmpty else { return nil }
            return "\(node.cssSelector) { \(declarations.joined(separator: " ")) }"
        }.joined(separator: "\n")
    }

    private static func rgba(_ color: CanonicalSolidColor) -> String {
        "rgba(\(number(color.red * 255)), \(number(color.green * 255)), \(number(color.blue * 255)), \(number(color.alpha)))"
    }

    private static func number(_ value: Double) -> String {
        let rounded = (value * 1_000).rounded() / 1_000
        var output = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        while output.contains(".") && output.last == "0" { output.removeLast() }
        if output.last == "." { output.append("0") }
        return output == "-0.0" ? "0.0" : output
    }
}

/// Closed base-sizing projection shared with the typed internal render tree.
/// No project-authored CSS fragments enter this declaration vocabulary.
enum StaticSizingOutputEmitter {
    static func emit(nodes: [InternalRenderTreeNode]) -> String {
        nodes.sorted { $0.id.description < $1.id.description }.compactMap { node in
            guard node.id == node.sourceNodeID,
                  node.cssSelector == CanonicalCSSRule.selector(for: node.id),
                  let sizing = node.sizingConstraints, sizing.isValid else { return nil }
            var declarations: [String] = []
            for (name, value) in [("min-width", sizing.minWidth), ("min-height", sizing.minHeight),
                                  ("max-width", sizing.maxWidth), ("max-height", sizing.maxHeight)] {
                if let value { declarations.append("\(name): \(value)px;") }
            }
            if sizing.aspectEnabled, let ratio = sizing.aspectRatio {
                declarations.append("aspect-ratio: \(ratio);")
            }
            guard !declarations.isEmpty else { return nil }
            return "\(node.cssSelector) { \(declarations.joined(separator: " ")) }"
        }.joined(separator: "\n")
    }
}

/// SF-1203 static-output v1: a content-free semantic outline gives a static
/// plan deterministic hierarchy provenance without changing markup structure,
/// introducing arbitrary HTML, or creating a browser/runtime path.
enum StaticSemanticOutlineEmitter {
    static func emit(trees: [InternalRenderTreeSnapshot]) -> String {
        trees.sorted { ($0.pageID?.description ?? "") < ($1.pageID?.description ?? "") }
            .flatMap { tree -> [String] in
                let knownIDs = Set(tree.nodes.map(\.id))
                let page = tree.pageID?.description ?? "-"
                return tree.nodes.sorted { $0.paintOrder < $1.paintOrder }.compactMap { node in
                    guard node.id == node.sourceNodeID,
                          SemanticHTMLElement(rawValue: node.semanticElement) != nil else {
                        return nil
                    }
                    let parent = node.parentNodeID.flatMap { knownIDs.contains($0) ? $0.description : nil } ?? "-"
                    return "\(page)\t\(node.id.description)\t\(parent)\t\(node.semanticElement)"
                }
            }
            .joined(separator: "\n")
    }
}

// SF-1206 foundation: build plans are deterministic and side-effect free.
struct LocalStaticBuildPlan: Equatable, Sendable {
    struct File: Equatable, Sendable { let path: String; let contents: String }
    struct BinaryFile: Equatable, Sendable { let path: String; let contents: Data }
    let revision: UInt64
    let files: [File]
    let binaryFiles: [BinaryFile]

    /// Deterministic in-memory integrity provenance. It detects a changed plan
    /// without creating a generated output file or exposing source content.
    let integrityDigest: String

    init(revision: UInt64, files: [File], binaryFiles: [BinaryFile] = []) {
        self.revision = revision
        self.files = files
        self.binaryFiles = binaryFiles
        let textMaterial = files.sorted { $0.path < $1.path }
            .map { "\($0.path.utf8.count):\($0.path)\u{0}\($0.contents.utf8.count):\($0.contents)" }
        let binaryMaterial = binaryFiles.sorted { $0.path < $1.path }
            .map { "\($0.path.utf8.count):\($0.path)\u{0}\($0.contents.count):\(ProjectResourceStore.digest($0.contents))" }
        integrityDigest = ProjectResourceStore.digest(Data((textMaterial + binaryMaterial).joined(separator: "\u{0}").utf8))
    }
}

enum LocalStaticBuildPlanner {
    static func plan(_ tree: InternalRenderTreeSnapshot) throws -> LocalStaticBuildPlan {
        .init(revision: tree.revision, files: [.init(path: "index.html", contents: try SafeHTMLEmitter.emit(tree)), .init(path: "styles.css", contents: try SafeCSSEmitter.emit(tree))])
    }
}

enum LocalStaticBuildWriteError: Error, Equatable, Sendable {
    case unsafeDestination, destinationExists, stale, cancelled, insufficientSpace, permissionDenied, writeFailed
}

enum LocalStaticBuildWriter {
    static func write(_ plan: LocalStaticBuildPlan, to destination: URL, expectedRevision: UInt64,
                      replacingExisting: Bool = false, cancelled: Bool = false,
                      cancellation: CooperativeCancellationCheckpoint = .init()) throws {
        guard !cancelled, !Task.isCancelled else { throw LocalStaticBuildWriteError.cancelled }
        guard plan.revision == expectedRevision else { throw LocalStaticBuildWriteError.stale }
        let target = destination.standardizedFileURL
        guard target.path != "/", !target.path.isEmpty,
              (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw LocalStaticBuildWriteError.unsafeDestination
        }
        let exists = FileManager.default.fileExists(atPath: target.path)
        guard !exists || replacingExisting else { throw LocalStaticBuildWriteError.destinationExists }
        let parent = target.deletingLastPathComponent()
        let stage = parent.appendingPathComponent(".siteforge-build-\(UUID().uuidString)", isDirectory: true)
        do {
            try cancellation.check()
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
            for file in plan.files {
                try cancellation.check()
                let output = try safeOutputURL(path: file.path, root: stage)
                try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                try file.contents.data(using: .utf8)!.write(to: output, options: .atomic)
            }
            for file in plan.binaryFiles {
                try cancellation.check()
                let output = try safeOutputURL(path: file.path, root: stage)
                try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                try file.contents.write(to: output, options: .atomic)
            }
            // Cancellation must still be observed after staging every byte,
            // before promoting/replacing the user-selected destination.
            try cancellation.check()
            if exists {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: stage,
                    backupItemName: nil, options: [])
            } else {
                try FileManager.default.moveItem(at: stage, to: target)
            }
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: stage); throw LocalStaticBuildWriteError.cancelled
        } catch let error as LocalStaticBuildWriteError {
            try? FileManager.default.removeItem(at: stage); throw error
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            try? FileManager.default.removeItem(at: stage); throw LocalStaticBuildWriteError.permissionDenied
        } catch let error as CocoaError where error.code == .fileWriteOutOfSpace {
            try? FileManager.default.removeItem(at: stage); throw LocalStaticBuildWriteError.insufficientSpace
        } catch {
            try? FileManager.default.removeItem(at: stage); throw LocalStaticBuildWriteError.writeFailed
        }
    }

    private static func safeOutputURL(path: String, root: URL) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else {
            throw LocalStaticBuildWriteError.unsafeDestination
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw LocalStaticBuildWriteError.unsafeDestination
        }
        // Normalize the existing stage once, before appending absent children.
        // macOS may normalize an existing /private/var root to /var while an
        // absent child retains /private/var; comparing those aliases rejects
        // safe output. Both sides must start from the same normalized root.
        let normalizedRoot = root.standardizedFileURL
        let output = components.reduce(normalizedRoot) { $0.appendingPathComponent(String($1), isDirectory: false) }
            .standardizedFileURL
        guard output.path.hasPrefix(normalizedRoot.path + "/") else {
            throw LocalStaticBuildWriteError.unsafeDestination
        }
        return output
    }
}

enum MultiPageStaticBuildError: Error, Equatable, Sendable { case invalidRoute, collision, invalidDocument }

enum MultiPageStaticBuildPlanner {
    static func plan(
        document: CanonicalDocument,
        imageOutputEntries: [StaticAssetExportEntry] = []
    ) throws -> LocalStaticBuildPlan {
        do { try document.validate() } catch { throw MultiPageStaticBuildError.invalidDocument }
        let reusableStyleIndex = try CanonicalReusableStyleIndex(document: document)
        let pages = try document.pages.filter { $0.role != .componentDefinition }.map {
            try ComponentGraphResolver.resolvedPage($0, in: document, breakpoint: .desktop)
        }
        let availablePageIDs = Set(pages.map(\.id))
        guard pages.allSatisfy({ CanonicalPageFlow.unsupportedStaticContainers($0,
            availablePageIDs: availablePageIDs).isEmpty }) else {
            throw MultiPageStaticBuildError.invalidDocument
        }
        let imageOutputPaths = staticImagePaths(
            assets: document.imageAssets,
            entries: imageOutputEntries
        )
        let imageAssets = Dictionary(uniqueKeysWithValues: document.imageAssets.map { ($0.id, $0) })
        var staticRoutes: [PageID: String] = [:]
        var sectionIDs: [PageID: Set<NodeID>] = [:]
        for page in pages {
            guard staticRoutes[page.id] == nil else { throw MultiPageStaticBuildError.invalidDocument }
            staticRoutes[page.id] = try outputPath(for: page)
            sectionIDs[page.id] = Set(page.canonicalDepthFirstNodes().filter { $0.kind == .section }.map(\.id))
        }
        var files: [LocalStaticBuildPlan.File] = []
        var paths = Set<String>()
        var staticNodes: [InternalRenderTreeNode] = []
        var staticTrees: [InternalRenderTreeSnapshot] = []
        var needsNavigationScript = false
        for page in pages.sorted(by: { $0.route.rawValue < $1.route.rawValue }) {
            let output = try outputPath(for: page)
            guard paths.insert(output).inserted else { throw MultiPageStaticBuildError.collision }
            let navigation = StaticNavigationEmitter.emit(
                StaticNavigationEmitter.entries(
                    pages: document.pages,
                    staticRoutes: staticRoutes,
                    currentPageID: page.id,
                    currentOutputPath: output
                )
            )
            let tree = try InternalDocumentRenderTreeCompiler.compile(
                page: page, documentID: document.id, revision: document.revision,
                staticRoutes: staticRoutes, sectionIDs: sectionIDs,
                imageOutputPaths: imageOutputPaths, imageAssets: imageAssets,
                colorTokens: document.colorTokens,
                reusableStyleIndex: reusableStyleIndex
            )
            staticNodes += tree.nodes
            staticTrees.append(tree)
            let body = try SafeHTMLEmitter.emit(tree, layoutContainers: ConnectedFluidOutputPolicy.wrapperIDs(page))
            let hasFlow = page.usesConnectedOutput
            let hasMenu = tree.nodes.contains { $0.navigation?.hamburgerEnabled == true }
            needsNavigationScript = needsNavigationScript || hasMenu
            let prefix = String(repeating: "../", count: max(0, output.split(separator: "/").count - 1))
            let stylesheetLink = hasFlow ? "<link rel=\"stylesheet\" href=\"\(prefix)styles.css\">" : ""
            let script = hasMenu ? "<script src=\"\(prefix)siteforge-navigation.js\" defer></script>" : ""
            let metadata = WebsiteMetadataResolver.resolve(page: page, document: document)
            guard let metadataHead = StaticSEOEmitter.head(.init(siteName: metadata.siteName,
                title: metadata.title, description: metadata.description, language: "en",
                index: metadata.allowsIndexing, follow: true), route: page.route.rawValue) else {
                throw MultiPageStaticBuildError.invalidDocument
            }
            let favicon = metadata.faviconAssetID.flatMap { imageOutputPaths[$0] }.map {
                "<link rel=\"icon\" href=\"\(prefix)\($0)\">"
            } ?? ""
            let head = "<head><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\(metadataHead)\(favicon)\(stylesheetLink)</head>"
            let markup: String
            if hasFlow {
                // Authored navigation replaces the generated route list; that
                // historical list must not shift the connected page origin.
                markup = "<!doctype html><html lang=\"en\">\(head)<body class=\"sf-connected-body\" tabindex=\"-1\"><div class=\"sf-connected-page sf-page-\(page.id)\">\(body)</div>\(script)</body></html>"
            } else {
                let contents = [navigation, body, script].filter { !$0.isEmpty }.joined(separator: "\n")
                markup = "<!doctype html><html lang=\"en\">\(head)<body>\(contents)</body></html>"
            }
            files.append(.init(path: output, contents: markup))
        }
        // The static build plan consumes the same typed responsive cascade as
        // editor layout. This remains an immutable planning artifact: it does
        // not create an authored CSS model or write a generated site.
        let layout = StaticLayoutOutputEmitter.emit(
            nodes: pages.filter { !$0.nodes.contains { CanonicalPageFlow.role($0) != nil } }
                .flatMap { $0.canonicalDepthFirstNodes() }
        )
        let typography = StaticTypographyOutputEmitter.emit(nodes: staticNodes)
        let images = StaticImageStyleOutputEmitter.emit(nodes: staticNodes)
        let fills = StaticFillLayerStyleOutputEmitter.emit(nodes: staticNodes)
        let boxStyles = StaticBoxStyleOutputEmitter.emit(nodes: staticNodes)
        let sizing = StaticSizingOutputEmitter.emit(nodes: staticNodes)
        let advancedStyles = StaticAdvancedStyleOutputEmitter.emit(nodes: staticNodes)
        let fluidTypography = StaticFluidValueOutputEmitter.emit(
            nodes: pages.flatMap { $0.canonicalDepthFirstNodes() },
            targets: [.fontSize, .lineHeight])
        // Fluid typography deliberately follows fixed typography. Geometry
        // and spacing fluid rules live inside layout output before explicit
        // breakpoint rules so authored breakpoint literals retain precedence.
        let stylesheet = [layout.css, typography, fluidTypography, images, fills, boxStyles, sizing, advancedStyles, ConnectedPageOutput.css(pages: pages, colorTokens: document.colorTokens)]
            .filter { !$0.isEmpty }.joined(separator: "\n")
        if !stylesheet.isEmpty {
            guard paths.insert("styles.css").inserted else { throw MultiPageStaticBuildError.collision }
            files.append(.init(path: "styles.css", contents: stylesheet))
        }
        if needsNavigationScript {
            guard paths.insert("siteforge-navigation.js").inserted else { throw MultiPageStaticBuildError.collision }
            files.append(.init(path: "siteforge-navigation.js", contents: ConnectedPageOutput.menuScript))
        }
        // The manifest is a plan-side integrity projection only. It names
        // verified content-addressed references but never carries resource
        // bytes or invokes the static writer.
        let assetManifest = StaticAssetManifestEmitter.emit(
            assets: document.imageAssets,
            entries: imageOutputEntries
        )
        if !assetManifest.isEmpty {
            guard paths.insert("assets.manifest.txt").inserted else { throw MultiPageStaticBuildError.collision }
            files.append(.init(path: "assets.manifest.txt", contents: assetManifest))
        }
        let semanticOutline = StaticSemanticOutlineEmitter.emit(trees: staticTrees)
        if !semanticOutline.isEmpty {
            guard paths.insert("semantic-outline.txt").inserted else { throw MultiPageStaticBuildError.collision }
            files.append(.init(path: "semantic-outline.txt", contents: semanticOutline))
        }
        files.append(.init(path: "manifest.txt", contents: files.map(\.path).sorted().joined(separator: "\n")))
        return .init(revision: document.revision, files: files)
    }

    /// Missing/corrupt output entries are represented by an in-bounds missing
    /// resource state in the static tree; the canonical AssetID remains intact.
    private static func staticImagePaths(
        assets: [ImageAsset],
        entries: [StaticAssetExportEntry]
    ) -> [AssetID: String] {
        Dictionary(uniqueKeysWithValues: assets.compactMap { asset -> (AssetID, String)? in
            guard let path = try? StaticImageOutputReferencePlanner.path(for: asset, entries: entries) else {
                return nil
            }
            return (asset.id, path)
        })
    }
    static func outputPath(for page: DocumentPage) throws -> String {
        let route = page.route.rawValue
        guard route.first == "/", !route.contains(".."), !route.contains("//"), !route.contains("?"), !route.contains("#") else { throw MultiPageStaticBuildError.invalidRoute }
        if page.role == .notFound { return "404.html" }
        if route == "/" { return "index.html" }
        let slug = String(route.dropFirst())
        guard !slug.isEmpty, slug.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "/" }) else { throw MultiPageStaticBuildError.invalidRoute }
        return slug + ".html"
    }

    /// A deterministic, content-redacted statement of static Form behavior.
    /// It is derived from canonical metadata and never represents a runtime
    /// destination, submitted value, or browser capability.
    static func formCompatibilityReport(document: CanonicalDocument) throws -> FormStaticBuildCompatibilityReport {
        let pages = document.pages.filter { $0.role != .componentDefinition }.sorted { $0.route.rawValue < $1.route.rawValue }
        let entries = try pages.map { page -> FormStaticBuildCompatibilityReport.Entry in
            let tree = try InternalDocumentRenderTreeCompiler.compile(page: page, documentID: document.id, revision: document.revision)
            let forms = tree.nodes.filter { $0.semanticElement == "form" }.map(\.id)
            let submitCount = tree.nodes.compactMap(\.formField).filter { $0.kind == "submit" }.count
            return .init(pageID: page.id, formNodeIDs: forms, disabledSubmitControlCount: submitCount)
        }
        return .init(documentID: document.id, revision: document.revision, entries: entries)
    }
}

/// SF-0202/SF-0303/SF-1102 v1: navigation is a pure output projection of the
/// ordered persisted website pages. It cannot add pages, alter routes, or
/// expose component/error implementation pages as public destinations.
struct StaticNavigationEntry: Equatable, Sendable {
    let pageID: PageID
    let route: PageRoute
    let label: String
    let href: String
    let isCurrent: Bool
}

enum StaticNavigationEmitter {
    static func entries(
        pages: [DocumentPage],
        staticRoutes: [PageID: String],
        currentPageID: PageID,
        currentOutputPath: String
    ) -> [StaticNavigationEntry] {
        pages.compactMap { page in
            // Preserve canonical navigator order. Not Found is a recovery
            // destination, and component definitions are authoring-only, so
            // neither is silently advertised as a public navigation item.
            guard page.role == .home || page.role == .standard,
                  let outputPath = staticRoutes[page.id],
                  let href = relativeHref(from: currentOutputPath, to: outputPath),
                  isSafeLabel(page.name) else { return nil }
            return .init(
                pageID: page.id,
                route: page.route,
                label: page.name,
                href: href,
                isCurrent: page.id == currentPageID
            )
        }
    }

    static func emit(_ entries: [StaticNavigationEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        let items = entries.map { entry in
            let current = entry.isCurrent ? " aria-current=\"page\"" : ""
            return "<li><a data-siteforge-page=\"\(entry.pageID.rawValue.uuidString.lowercased())\" href=\"\(escape(entry.href))\"\(current)>\(escape(entry.label))</a></li>"
        }.joined()
        return "<nav aria-label=\"Site\"><ul>\(items)</ul></nav>"
    }

    private static func isSafeLabel(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        value.utf8.count <= 256 &&
        !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    /// Output paths are package-generated, but this remains defensive because
    /// the emitter is independently callable in compiler tests. A nested page
    /// must link relatively so the generated plan also works without a server
    /// that rewrites every route at the site root.
    private static func relativeHref(from currentOutputPath: String, to targetOutputPath: String) -> String? {
        guard isSafeOutputPath(currentOutputPath), isSafeOutputPath(targetOutputPath) else { return nil }
        let currentDirectory = Array(currentOutputPath.split(separator: "/").dropLast())
        let target = targetOutputPath.split(separator: "/")
        var common = 0
        while common < currentDirectory.count, common < target.count,
              currentDirectory[currentDirectory.index(currentDirectory.startIndex, offsetBy: common)] == target[target.index(target.startIndex, offsetBy: common)] {
            common += 1
        }
        let parentCount = currentDirectory.count - common
        let targetStart = target.index(target.startIndex, offsetBy: common)
        let components = Array(repeating: "..", count: parentCount) + target[targetStart...].map(String.init)
        return components.joined(separator: "/")
    }

    private static func isSafeOutputPath(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("\\"), !value.contains("//") else { return false }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return false }
        return components.allSatisfy { component in
            component.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }
        }
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

struct FormStaticBuildCompatibilityReport: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let pageID: PageID
        let formNodeIDs: [NodeID]
        let disabledSubmitControlCount: Int
    }
    let documentID: DocumentID
    let revision: UInt64
    let entries: [Entry]
    /// Stable category, intentionally independent from live validation types.
    let submissionBehavior = "unavailableSubmission"
}

// SF-1207 v1 metadata is typed and emitted only from approved route paths.
struct StaticSEOMetadata: Equatable, Sendable {
    let siteName: String; let title: String; let description: String?; let language: String; let index: Bool; let follow: Bool
}

enum StaticSEOEmitter {
    static func head(_ metadata: StaticSEOMetadata, route: String) -> String? {
        guard !metadata.siteName.isEmpty, !metadata.title.isEmpty, route.first == "/", !route.contains("?") && !route.contains("#") else { return nil }
        func escape(_ value: String) -> String { value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;") }
        let description = metadata.description.map { "<meta name=\"description\" content=\"\(escape($0))\">" } ?? ""
        return "<meta charset=\"utf-8\"><title>\(escape(metadata.title))</title>\(description)<meta name=\"robots\" content=\"\(metadata.index ? "index" : "noindex"), \(metadata.follow ? "follow" : "nofollow")\"><link rel=\"canonical\" href=\"\(escape(route))\">"
    }
}

// SF-1208/SF-1211 v1: profile selection is an explicit noncanonical request.
enum LocalBuildProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case development, staticRelease
    var id: String { rawValue }
    var title: String { self == .development ? "Development" : "Static Release" }
}

struct LocalBuildProfileSelection: Codable, Equatable, Sendable {
    static let currentVersion = 1
    let version: Int
    let profile: LocalBuildProfile

    init(profile: LocalBuildProfile, version: Int = currentVersion) {
        self.version = version; self.profile = profile
    }

    func validate() throws {
        guard version == Self.currentVersion else { throw MultiPageStaticBuildError.invalidDocument }
    }
}
struct LocalBuildReport: Equatable, Sendable {
    let revision: UInt64
    let profile: LocalBuildProfile
    let filePaths: [String]
    let deferredCapabilities: [String]
}

enum LocalBuildProfileCompiler {
    static func compile(_ plan: LocalStaticBuildPlan, profile: LocalBuildProfile) -> (LocalStaticBuildPlan, LocalBuildReport) {
        let files = plan.files.sorted { $0.path < $1.path }.map { file in
            let contents: String
            switch profile {
            case .development: contents = file.contents
            case .staticRelease:
                if file.path.hasSuffix(".css") {
                    var seen = Set<String>()
                    contents = file.contents.split(separator: "\n").map(String.init)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty && seen.insert($0).inserted }
                        .joined(separator: "\n")
                } else {
                    contents = file.contents
                }
            }
            return LocalStaticBuildPlan.File(path: file.path, contents: contents)
        }
        return (.init(revision: plan.revision, files: files, binaryFiles: plan.binaryFiles.sorted { $0.path < $1.path }),
                .init(revision: plan.revision, profile: profile,
                      filePaths: (files.map(\.path) + plan.binaryFiles.map(\.path)).sorted(),
                      deferredCapabilities: ["custom-code", "publishing", "remote-runtime"]))
    }
}

enum StaticBuildFindingSeverity: String, CaseIterable, Codable, Sendable {
    case error, warning, information, unsupported, policyBlocked = "policy-blocked"
}

struct StaticBuildFinding: Identifiable, Equatable, Sendable {
    let id: String
    let severity: StaticBuildFindingSeverity
    let code: String
    let requirementID: String
    let affectedNodeID: NodeID?
    let outputPath: String?
    let explanation: String
    let repair: String

    init(severity: StaticBuildFindingSeverity, code: String, requirementID: String,
         affectedNodeID: NodeID? = nil, outputPath: String? = nil,
         explanation: String, repair: String) {
        self.severity = severity; self.code = code; self.requirementID = requirementID
        self.affectedNodeID = affectedNodeID; self.outputPath = outputPath
        self.explanation = explanation; self.repair = repair
        let identity = affectedNodeID.map {
            DiagnosticStableIdentifier.sanitize($0.description, domain: .staticBuild, kind: "node")
        } ?? "project"
        id = "\(requirementID):\(code):\(identity):\(outputPath ?? "-")"
    }

    var redactedSummary: String {
        let identity = affectedNodeID.map {
            DiagnosticStableIdentifier.sanitize($0.description, domain: .staticBuild, kind: "node")
        } ?? "project"
        return "[\(severity.rawValue)] \(code) · \(requirementID) · \(identity) · \(explanation) Repair: \(repair)"
    }
}

struct StaticBuildCompilation: Equatable, Sendable {
    let documentID: DocumentID
    let revision: UInt64
    let profile: LocalBuildProfile
    let plan: LocalStaticBuildPlan?
    let report: LocalBuildReport?
    let findings: [StaticBuildFinding]

    var canWrite: Bool { plan != nil && !findings.contains { $0.severity == .error } }
    var redactedSummary: String {
        let heading = "Static build \(profile.title), revision \(revision): \(findings.count) finding(s)."
        return ([heading] + findings.map(\.redactedSummary)).joined(separator: "\n")
    }
}

/// Findings belong to one attempt, not to the retained last successful plan.
/// This receipt is editor state only; equality includes the complete finding,
/// not merely a repeatable diagnostic code or an arbitrary caller's node ID.
struct StaticBuildFindingReceipt: Equatable, Sendable {
    let id: UUID
    let documentID: DocumentID
    let revision: UInt64
    let findings: [StaticBuildFinding]

    init(id: UUID = UUID(), compilation: StaticBuildCompilation) {
        self.id = id; documentID = compilation.documentID
        revision = compilation.revision; findings = compilation.findings
    }
    func contains(_ finding: StaticBuildFinding, document: CanonicalDocument) -> Bool {
        documentID == document.id && revision == document.revision && findings.contains(finding)
    }
}

enum StaticBuildFindingEditor: Equatable, Sendable {
    case object, pageContents, layout, designBox
    static func destination(for finding: StaticBuildFinding, node: DocumentNode) -> Self {
        let isPageChrome = CanonicalPageFlow.role(node).map { $0 == .header || $0 == .footer } == true
        return switch finding.code {
        case "page-flow-navigation-room" where isPageChrome: .pageContents
        case "page-flow-positioning": .layout
        case "page-flow-navigation-clipped" where isPageChrome: .designBox
        default: .object
        }
    }
    var title: String {
        switch self {
        case .object: "Show Object"
        case .pageContents: "Open Header/Footer Settings"
        case .layout: "Open Layout"
        case .designBox: "Open Design"
        }
    }
}

enum StaticBuildFindingRevealAvailability: Equatable {
    case action(String), unavailable(String), noTarget
}

struct StaticBuildFindingTarget: Equatable, Sendable {
    enum Failure: Error, Equatable {
        case staleDocument, staleRevision, foreignFinding, noObject, missingObject, lockedOrHidden
        var recovery: String {
            switch self {
            case .staleDocument, .staleRevision, .foreignFinding:
                "Check the current project and revision again; these results are no longer current."
            case .noObject:
                "Follow the listed repair instruction; this finding has no exact object editor."
            case .missingObject:
                "The original object is unavailable. Restore it with Undo or check the document again."
            case .lockedOrHidden:
                "This object is locked or hidden at this screen size. Review its state in Layers; no value will be changed automatically."
            }
        }
    }
    let pageID: PageID
    let nodeID: NodeID
    let destination: StaticBuildFindingEditor
    static func prepare(_ finding: StaticBuildFinding, receipt: StaticBuildFindingReceipt,
                        document: CanonicalDocument, breakpoint: ResponsiveBreakpoint) throws -> Self {
        guard receipt.documentID == document.id else { throw Failure.staleDocument }
        guard receipt.revision == document.revision else { throw Failure.staleRevision }
        guard receipt.findings.contains(finding) else { throw Failure.foreignFinding }
        guard let id = finding.affectedNodeID else { throw Failure.noObject }
        guard let page = document.pages.first(where: { $0.nodes.contains { $0.id == id } }),
              let node = page.nodes.first(where: { $0.id == id }) else { throw Failure.missingObject }
        guard !node.selectionBooleanProperty("locked"), page.effectiveVisibleNodeIDs(breakpoint: breakpoint).contains(id)
            else { throw Failure.lockedOrHidden }
        return .init(pageID: page.id, nodeID: id, destination: .destination(for: finding, node: node))
    }
}

/// Closed static compiler entry point. It consumes one immutable document plus
/// caller-owned resource bytes and returns an immutable plan or typed findings.
/// It never reads paths, writes output, mutates the project, or publishes.
enum StaticBuildCompiler {
    /// Safari and local export resolve the same immutable package input on
    /// their workers. Never assemble/hash resource bytes in a SwiftUI event.
    static func compile(document: CanonicalDocument, profileSelection: LocalBuildProfileSelection,
                        package: ProjectPackage) -> StaticBuildCompilation {
        do {
            let input = try ProjectImageResourceSnapshot(document: document, package: package)
            return compile(document: document, profileSelection: profileSelection,
                resourceDescriptors: input.descriptors, resourceData: input.data, cancelled: Task.isCancelled)
        } catch is CancellationError {
            return compile(document: document, profileSelection: profileSelection,
                resourceDescriptors: [:], resourceData: [:], cancelled: true)
        } catch {
            return .init(documentID: document.id, revision: document.revision, profile: profileSelection.profile,
                plan: nil, report: nil, findings: [.init(severity: .error, code: "resource-snapshot-invalid",
                    requirementID: "SF-1206-004", explanation: "The resource snapshot is unavailable or belongs to another project.",
                    repair: "Refresh from the current project. Locate or replace missing resources before exporting.")])
        }
    }

    static func compile(
        document: CanonicalDocument,
        profileSelection: LocalBuildProfileSelection,
        resourceDescriptors: [ResourceID: ProjectResourceDescriptor],
        resourceData: [ResourceID: Data],
        cancelled: Bool = false
    ) -> StaticBuildCompilation {
        var findings: [StaticBuildFinding] = []
        do { try profileSelection.validate() }
        catch {
            findings.append(.init(severity: .error, code: "profile-version-unsupported",
                requirementID: "SF-1208-004", explanation: "The build profile version is unsupported.",
                repair: "Choose a current built-in profile."))
            return .init(documentID: document.id, revision: document.revision,
                         profile: profileSelection.profile, plan: nil, report: nil, findings: findings)
        }
        guard !cancelled else {
            findings.append(.init(severity: .information, code: "cancelled",
                requirementID: "SF-1208-004", explanation: "The build was cancelled before output planning.",
                repair: "Run the build again when ready."))
            return .init(documentID: document.id, revision: document.revision,
                         profile: profileSelection.profile, plan: nil, report: nil, findings: findings)
        }

        // Compatibility policy builds identity-indexed views. Reject invalid
        // canonical input before those dictionaries, not after output planning.
        do { try document.validate() }
        catch {
            findings.append(.init(severity: .error, code: "plan-invalid",
                requirementID: "SF-1211-004", explanation: "Canonical document validation failed before compatibility planning.",
                repair: "Restore the last valid document or undo the invalid edit, then preflight again."))
            return .init(documentID: document.id, revision: document.revision,
                profile: profileSelection.profile, plan: nil, report: nil, findings: findings)
        }
        let nodes = document.pages.flatMap { $0.canonicalDepthFirstNodes() }
        for original in document.websitePages {
            let page = (try? ComponentGraphResolver.resolvedPage(original, in: document, breakpoint: .desktop)) ?? original
            let failures = CanonicalPageFlow.outputFailures(page,
                availablePageIDs: Set(document.websitePages.map(\.id)))
            for id in failures.keys.sorted(by: { $0.description < $1.description }) {
                guard let failure = failures[id] else { continue }
                findings.append(.init(severity: .error, code: failure.code,
                    requirementID: "SF-0501-004", affectedNodeID: id,
                    explanation: failure.explanation, repair: failure.repair))
            }
        }
        for instance in document.websitePages.flatMap(\.nodes) where instance.kind == .component {
            do {
                let conflicts = try CanonicalComponentOverrides.conflicts(instance: instance, document: document)
                if !conflicts.isEmpty {
                    findings.append(.init(severity: .error, code: "component-override-conflict",
                        requirementID: "SF-0905-004", affectedNodeID: instance.id,
                        explanation: "A component instance retains unresolved authored overrides (\(conflicts.count)).",
                        repair: "Restore the definition binding, reset the unresolved values, or detach after resolving them."))
                } else if try CanonicalComponentOverrides.requiresRecovery(instance: instance, document: document) {
                    findings.append(.init(severity: .error, code: "component-definition-unavailable",
                        requirementID: "SF-0901-004", affectedNodeID: instance.id,
                        explanation: "A component reference has no available original definition.",
                        repair: "Restore the original definition identity before building output."))
                }
            } catch {
                findings.append(.init(severity: .error, code: "component-override-invalid",
                    requirementID: "SF-0905-008", affectedNodeID: instance.id,
                    explanation: "A component override path cannot be resolved safely.",
                    repair: "Review the component definition and reset invalid instance values."))
            }
        }
        guard !findings.contains(where: { $0.severity == .error }) else {
            return .init(documentID: document.id, revision: document.revision,
                         profile: profileSelection.profile, plan: nil, report: nil,
                         findings: findings.sorted { $0.id < $1.id })
        }
        func referencedAssetID(_ node: DocumentNode) -> AssetID? {
            CanonicalImageStyle.resolve(node)?.assetID ?? CanonicalImageFill.resolve(node)?.assetID
        }
        let referencedAssets = document.imageAssets.filter { asset in
            nodes.contains { referencedAssetID($0) == asset.id } || document.websiteMetadata?.faviconAssetID == asset.id
        }.sorted { $0.id.description < $1.id.description }
        var entries: [StaticAssetExportEntry] = []
        var binaries: [LocalStaticBuildPlan.BinaryFile] = []
        if let favicon = document.websiteMetadata?.faviconAssetID,
           !document.imageAssets.contains(where: { $0.id == favicon }) {
            findings.append(.init(severity: .error, code: "favicon-missing",
                requirementID: "SF-1207-004", explanation: "The website favicon is unavailable.",
                repair: "Choose a replacement image or remove the favicon in Site Settings."))
        }
        for asset in referencedAssets {
            let affected = nodes.first { referencedAssetID($0) == asset.id }?.id
            guard let descriptor = resourceDescriptors[asset.resourceID],
                  let bytes = resourceData[asset.resourceID] else {
                findings.append(.init(severity: .error, code: "asset-missing",
                    requirementID: "SF-1206-004", affectedNodeID: affected,
                    explanation: "A referenced image resource is unavailable.",
                    repair: "Locate, replace, or detach the missing image in Assets."))
                continue
            }
            do {
                let planned = try StaticAssetExportPlanner.plan(
                    index: .init(resources: [descriptor]), blobs: [descriptor.sha256: bytes])
                guard let entry = planned.first, entry.sha256 == asset.contentHash else {
                    throw StaticAssetExportError.corrupt
                }
                entries.append(entry)
                binaries.append(.init(path: entry.outputPath, contents: bytes))
            } catch let error as StaticAssetExportError {
                let code: String = switch error {
                case .unsupported: "asset-unsupported"
                case .corrupt: "asset-corrupt"
                case .oversized: "asset-oversized"
                }
                findings.append(.init(severity: error == .unsupported ? .unsupported : .error,
                    code: code, requirementID: "SF-1206-004", affectedNodeID: affected,
                    explanation: "A referenced image cannot be exported safely.",
                    repair: "Replace the image with a supported intact PNG or JPEG."))
            } catch {
                findings.append(.init(severity: .error, code: "asset-invalid",
                    requirementID: "SF-1206-004", affectedNodeID: affected,
                    explanation: "A referenced image failed closed validation.",
                    repair: "Replace or detach the affected image."))
            }
        }
        guard !findings.contains(where: { $0.severity == .error }) else {
            return .init(documentID: document.id, revision: document.revision,
                         profile: profileSelection.profile, plan: nil, report: nil,
                         findings: findings.sorted { $0.id < $1.id })
        }
        do {
            let base = try MultiPageStaticBuildPlanner.plan(document: document, imageOutputEntries: entries)
            let withAssets = LocalStaticBuildPlan(revision: base.revision, files: base.files,
                binaryFiles: binaries.sorted { $0.path < $1.path })
            let compiled = LocalBuildProfileCompiler.compile(withAssets, profile: profileSelection.profile)
            let formReport = try MultiPageStaticBuildPlanner.formCompatibilityReport(document: document)
            if formReport.entries.contains(where: { $0.disabledSubmitControlCount > 0 }) {
                findings.append(.init(severity: .policyBlocked, code: "form-submission-unconfigured",
                    requirementID: "SF-1211-003",
                    explanation: "Static Form submit controls remain disabled because no destination is configured.",
                    repair: "Keep the safe disabled control or configure submission in a future supported workflow."))
            }
            findings.append(.init(severity: .information, code: "publishing-excluded",
                requirementID: "SF-1208-003", explanation: "The build produces local static files only.",
                repair: "Choose an explicit local destination; publishing remains unavailable."))
            return .init(documentID: document.id, revision: document.revision,
                         profile: profileSelection.profile, plan: compiled.0, report: compiled.1,
                         findings: findings.sorted { $0.id < $1.id })
        } catch {
            findings.append(.init(severity: .error, code: "plan-invalid",
                requirementID: "SF-1211-004", explanation: "The static plan could not be produced safely.",
                repair: "Review page routes and compatibility findings, then run preflight again."))
            return .init(documentID: document.id, revision: document.revision,
                         profile: profileSelection.profile, plan: nil, report: nil,
                         findings: findings.sorted { $0.id < $1.id })
        }
    }
}

// SF-1203 v1 output is intentionally in-memory only. The fixed vocabulary and
// allowlist prevent authored content from becoming executable markup.
enum SafeHTMLEmissionError: Error, Equatable, Sendable { case unsupportedTag, invalidIdentity, invalidFormField, invalidControl }

enum SafeHTMLEmitter {
    static func emit(_ tree: InternalRenderTreeSnapshot, layoutContainers: Set<NodeID> = []) throws -> String {
        let ordered = tree.nodes.sorted { $0.paintOrder < $1.paintOrder }
        let structured = ordered.contains(where: \.usesConnectedLayout)
        guard Set(ordered.map(\.id)).count == ordered.count else { throw SafeHTMLEmissionError.invalidIdentity }
        let byID = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
        guard layoutContainers.isSubset(of: Set(byID.keys)) else { throw SafeHTMLEmissionError.invalidIdentity }
        let children = Dictionary(grouping: ordered.filter { $0.parentNodeID != nil }, by: { $0.parentNodeID! })
        let formIDs = Set(ordered.filter { $0.semanticElement == "form" }.map(\.id))
        let fieldsByForm = Dictionary(grouping: ordered.compactMap { node -> InternalRenderTreeNode? in
            node.formField == nil ? nil : node
        }, by: { $0.formField!.formID })
        guard Set(fieldsByForm.keys).isSubset(of: formIDs) else { throw SafeHTMLEmissionError.invalidFormField }
        if structured {
            for node in ordered {
                var parent = node.parentNodeID, visited: Set<NodeID> = [node.id]
                while let id = parent {
                    guard let ancestor = byID[id], visited.insert(id).inserted, visited.count <= 257 else {
                        throw SafeHTMLEmissionError.invalidIdentity
                    }
                    parent = ancestor.parentNodeID
                }
            }
        }
        func hasFlowAncestor(_ node: InternalRenderTreeNode) throws -> Bool {
            var parent = node.parentNodeID, visited = Set<NodeID>()
            while let id = parent, let ancestor = byID[id] {
                guard visited.insert(id).inserted, visited.count <= 256 else { throw SafeHTMLEmissionError.invalidIdentity }
                if structured || ancestor.pageFlowRole != nil { return true }
                parent = ancestor.parentNodeID
            }
            return false
        }
        func render(_ node: InternalRenderTreeNode, nested: Bool = false, depth: Int = 0) throws -> String {
            guard depth <= 256 else { throw SafeHTMLEmissionError.invalidIdentity }
            if node.semanticElement == "form" {
                let identifier = try validatedIdentifier(node)
                let fields = try (fieldsByForm[node.id] ?? []).map { try emitField($0, formIDs: formIDs) }.joined()
                let accessibility = accessibilityAttributes(node)
                return "<form data-siteforge-node=\"\(identifier)\" class=\"sf-node-\(identifier)\"\(accessibility)>\(fields)</form>"
            }
            var markup = try emitNode(node, formIDs: formIDs)
            if (structured || node.pageFlowRole != nil || nested), node.semanticElement != "img", node.control == nil {
                let content = try (children[node.id] ?? []).filter { $0.navigationOwnerID == nil && $0.formField == nil }
                    .map { try render($0, nested: true, depth: depth + 1) }.joined()
                let nav = try node.navigation.map { try navigationHTML($0, owner: node.id, role: node.pageFlowRole ?? $0.role) } ?? ""
                let close = "</\(node.semanticElement)>"
                let body = layoutContainers.contains(node.id)
                    ? "<div class=\"\(ConnectedFluidOutputPolicy.wrapperClass(node.id))\">\(content)</div>" : content
                if markup.hasSuffix(close) { markup = String(markup.dropLast(close.count)) + nav + body + close }
            }
            return markup
        }
        var fragments: [String] = []
        for node in ordered where node.formField == nil && node.navigationOwnerID == nil {
            if try !hasFlowAncestor(node) { fragments.append(try render(node)) }
        }
        return fragments.joined(separator: "\n")
    }

    private static func navigationHTML(_ navigation: InternalStaticNavigation, owner: NodeID, role: PageFlowRole?) throws -> String {
        guard navigation.links.count <= CanonicalPageFlow.maximumLinks,
              Set(navigation.links.map(\.id)).count == navigation.links.count else { throw SafeHTMLEmissionError.invalidControl }
        let links = try navigation.links.map { link -> String in
            guard !link.label.isEmpty, link.label.utf8.count <= 256,
                  !link.label.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw SafeHTMLEmissionError.invalidControl }
            let label = escape(link.label), id = link.id.description
            if let href = link.href {
                guard !href.contains(":"), !href.contains("\\"), !href.hasPrefix("//"),
                      !href.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw SafeHTMLEmissionError.invalidControl }
                return "<a class=\"sf-node-\(id) sf-nav-link-\(id)\" data-siteforge-nav-link=\"\(id)\" href=\"\(escape(href))\"\(link.isCurrentPage ? " aria-current=\"page\"" : "")\(link.opensNewContext ? " target=\"_blank\" rel=\"noopener noreferrer\"" : "") title=\"\(label)\">\(label)</a>"
            }
            return "<a class=\"sf-node-\(id) sf-nav-link-\(id)\" data-siteforge-nav-link=\"\(id)\" role=\"link\" aria-disabled=\"true\" tabindex=\"0\" title=\"Missing original page\">\(label)</a>"
        }.joined()
        let name = role == .footer ? "Footer navigation" : "Header navigation"
        let hasMenu = navigation.hamburgerEnabled && navigation.links.contains { $0.href != nil }
        let inline = "<nav aria-label=\"\(name)\" class=\"sf-nav-inline\(hasMenu ? " sf-nav-responsive" : "")\">\(links)</nav>"
        let panelID = "sf-nav-panel-\(owner)"
        let menu = hasMenu ? "<details class=\"sf-nav-menu\" data-siteforge-navigation=\"\(owner.description)\"><summary aria-label=\"\(name) menu\" aria-controls=\"\(panelID)\" aria-expanded=\"false\"><span aria-hidden=\"true\">☰</span> Menu</summary><nav id=\"\(panelID)\" aria-label=\"\(name)\">\(links)</nav></details>" : ""
        return "<div class=\"sf-page-navigation sf-page-navigation-\(owner)\">\(inline)\(menu)</div>"
    }

    private static func emitNode(_ node: InternalRenderTreeNode, formIDs: Set<NodeID>) throws -> String {
        let allowed = Set(["div", "section", "main", "header", "footer", "nav", "article", "aside", "p", "h1", "h2", "h3", "h4", "h5", "h6", "img", "button", "a", "form"])
        guard allowed.contains(node.semanticElement) else { throw SafeHTMLEmissionError.unsupportedTag }
        let identifier = try validatedIdentifier(node)
        if node.formField != nil {
            return try emitField(node, formIDs: formIDs)
        }
        let anchor = node.anchorID.map { " id=\"\(escape($0))\"" } ?? ""
        let attributes = " data-siteforge-node=\"\(identifier)\" class=\"sf-node-\(identifier)\"\(anchor)\(accessibilityAttributes(node))"
        if let control = node.control {
            let label = escape(control.label)
            if control.isLink {
                if let href = control.href {
                    let newContext = control.opensNewContext ? " target=\"_blank\" rel=\"noopener noreferrer\"" : ""
                    return "<a\(attributes) href=\"\(escape(href))\"\(newContext)>\(label)</a>"
                }
                return "<a\(attributes) role=\"link\" aria-disabled=\"true\">\(label)</a>"
            }
            return "<button\(attributes) type=\"button\"\(control.disabled ? " disabled aria-disabled=\"true\"" : "")>\(label)</button>"
        }
        if node.semanticElement == "img" {
            return try emitImage(node, attributes: attributes)
        }
        // Text is canonical plain content, not a markup fragment. Invalid
        // historical content is safely omitted from static output rather than
        // becoming executable or malformed HTML.
        let content = node.textContent.flatMap(safeTextContent).map(escape) ?? ""
        if node.isManagedChromeTitle, node.typography != nil {
            return "<\(node.semanticElement)\(attributes)><span data-siteforge-text>\(content)</span></\(node.semanticElement)>"
        }
        return "<\(node.semanticElement)\(attributes)>\(content)</\(node.semanticElement)>"
    }

    private static func accessibilityAttributes(_ node: InternalRenderTreeNode) -> String {
        let name = node.accessibilityName.map { " aria-label=\"\(escape($0))\"" } ?? ""
        let help = node.accessibilityHelp.map { " aria-description=\"\(escape($0))\"" } ?? ""
        return name + help
    }

    private static func emitField(_ node: InternalRenderTreeNode, formIDs: Set<NodeID>) throws -> String {
        guard let field = node.formField else { throw SafeHTMLEmissionError.invalidFormField }
        let identifier = try validatedIdentifier(node)
            guard node.semanticElement == "p", formIDs.contains(field.formID),
                  ["text", "email", "textarea", "checkbox", "select", "submit"].contains(field.kind),
                  field.name.range(of: "^[A-Za-z][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil,
                  validText(field.label, maximum: 256),
                  field.help.map({ validText($0, maximum: 512) }) ?? true else {
                throw SafeHTMLEmissionError.invalidFormField
            }
            if field.kind == "select" {
                guard validOptions(field.options) else { throw SafeHTMLEmissionError.invalidFormField }
            } else {
                guard field.options.isEmpty else { throw SafeHTMLEmissionError.invalidFormField }
            }
            let controlID = "sf-field-\(identifier)"
            let required = field.required ? " required" : ""
            let escapedName = escape(field.name)
            let help = field.help.map { "<span id=\"\(controlID)-help\">\(escape($0))</span>" } ?? ""
            let describedBy = field.help == nil ? "" : " aria-describedby=\"\(controlID)-help\""
            let control: String
            let maximumLength = field.maximumLength.map { " maxlength=\"\($0)\"" } ?? ""
            switch field.kind {
            case "textarea":
                control = "<textarea id=\"\(controlID)\" name=\"\(escapedName)\"\(describedBy)\(required)\(maximumLength)></textarea>"
            case "select":
                let options = field.options.map { "<option value=\"\(escape($0.value))\">\(escape($0.label))</option>" }.joined()
                control = "<select id=\"\(controlID)\" name=\"\(escapedName)\"\(describedBy)\(required)>\(options)</select>"
            case "submit":
                // Submission wiring is deliberately deferred: the emitted
                // control remains keyboard-accessible but cannot navigate or
                // exfiltrate data without an explicitly configured route.
                control = "<button id=\"\(controlID)\" type=\"submit\" disabled aria-disabled=\"true\" data-siteforge-submission=\"unconfigured\">\(escape(field.label))</button>"
            default:
                control = "<input id=\"\(controlID)\" name=\"\(escapedName)\" type=\"\(field.kind)\"\(describedBy)\(required)\(maximumLength)>"
            }
            return "<label for=\"\(controlID)\">\(escape(field.label))</label>\(control)\(help)"
    }

    private static func emitImage(_ node: InternalRenderTreeNode, attributes: String) throws -> String {
        guard let image = node.image else { return "<img\(attributes) data-siteforge-asset-state=\"missing\">" }
        let resource = " data-siteforge-asset=\"\(escape(image.assetID.description))\""
        let dimensions: String
        if let width = image.intrinsicWidth,
           let height = image.intrinsicHeight,
           (1...ImageAsset.maximumPixelDimension).contains(width),
           (1...ImageAsset.maximumPixelDimension).contains(height) {
            dimensions = " width=\"\(width)\" height=\"\(height)\""
        } else {
            dimensions = ""
        }
        let source: String
        if let path = image.outputPath, isVerifiedAssetPath(path) {
            source = " src=\"\(escape(path))\""
        } else {
            source = " data-siteforge-asset-state=\"missing\""
        }
        if image.isDecorative {
            return "<img\(attributes)\(resource)\(source)\(dimensions) alt=\"\" role=\"presentation\">"
        }
        let alt = safeTextContent(image.altText) ?? ""
        return "<img\(attributes)\(resource)\(source)\(dimensions) alt=\"\(escape(alt))\">"
    }

    private static func validatedIdentifier(_ node: InternalRenderTreeNode) throws -> String {
        let identifier = node.id.rawValue.uuidString.lowercased()
        guard identifier == node.sourceNodeID.rawValue.uuidString.lowercased() else { throw SafeHTMLEmissionError.invalidIdentity }
        return identifier
    }

    private static func validText(_ value: String, maximum: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        value.count <= maximum &&
        !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func safeTextContent(_ value: String) -> String? {
        guard value.utf8.count <= CanonicalComponentText.maximumTextBytes,
              !value.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
                      && $0.value != 10 && $0.value != 13 && $0.value != 9
              }) else {
            return nil
        }
        return value
    }

    private static func isVerifiedAssetPath(_ value: String) -> Bool {
        value.range(of: "^assets/[a-f0-9]{64}\\.(png|jpg)$", options: .regularExpression) != nil
    }

    private static func validOptions(_ options: [InternalFormOption]) -> Bool {
        !options.isEmpty && options.count <= CanonicalFormSelectOptions.maximumOptions &&
        Set(options.map(\.id)).count == options.count && Set(options.map(\.value)).count == options.count &&
        options.allSatisfy { validText($0.label, maximum: CanonicalFormSelectOptions.maximumTextLength) && validText($0.value, maximum: CanonicalFormSelectOptions.maximumTextLength) }
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

struct CanvasRenderTileID: Codable, Hashable, Comparable, Sendable {
    let column: Int
    let row: Int
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row ? lhs.column < rhs.column : lhs.row < rhs.row
    }
}

struct CanvasRenderTile: Equatable, Sendable {
    let id: CanvasRenderTileID
    let deviceFrame: DeviceRect
    let objectIDs: [NodeID]
    let estimatedBytes: Int
}

struct CanvasAccessibilityElementSnapshot: Equatable, Sendable {
    let id: CanvasAccessibilityID
    let objectID: NodeID
    let label: String
    let help: String?
    let frame: ViewportRect
    let paintOrder: Int
    let textContent: String?

    init(id: CanvasAccessibilityID, objectID: NodeID, label: String, help: String? = nil,
         frame: ViewportRect, paintOrder: Int, textContent: String? = nil) {
        self.id = id; self.objectID = objectID; self.label = label; self.frame = frame
        self.help = help; self.paintOrder = paintOrder; self.textContent = textContent
    }
}

enum CanvasAccessibilityFocusPolicy {
    static func repairedFocus(
        previousObjectID: NodeID?,
        elements: [CanvasAccessibilityElementSnapshot]
    ) -> NodeID? {
        guard !elements.isEmpty else { return nil }
        if let previousObjectID, elements.contains(where: { $0.objectID == previousObjectID }) {
            return previousObjectID
        }
        return elements.first?.objectID
    }
}

enum CanvasInvalidationKind: String, Codable, Sendable {
    case initial, dirtyRegions, compositorOnly, fullRaster
}

struct CanvasRenderPlan: Equatable, Sendable {
    let identity: CanvasRenderRequestIdentity
    let surfaceID: CanvasRenderSurfaceID
    /// The immutable viewport snapshot used to allocate this plan's tiles.
    /// Native composition must never substitute a newer live viewport while
    /// adopting the plan; that would separate painted bounds from overlays.
    let viewport: CanvasViewportState
    let authoredObjects: [CanvasRenderObject]
    let pageBackground: CanvasRenderObject?
    var paintObjects: [CanvasRenderObject] { pageBackground.map { [$0] + authoredObjects } ?? authoredObjects }
    let tiles: [CanvasRenderTile]
    let accessibilityElements: [CanvasAccessibilityElementSnapshot]
    let dirtyWorldRegions: [WorldRect]
    let invalidation: CanvasInvalidationKind
    let deterministicDigest: String
}

enum CanvasRendererError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedSchema(Int)
    case emptyScene
    case duplicateObject(NodeID)
    case duplicatePaintOrder(Int)
    case invalidObject(NodeID)
    case objectLimitExceeded(Int)
    case tileLimitExceeded(Int)
    case rasterLimitExceeded
    case cacheLimitExceeded
    case cancelled
    case staleResult

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema: "This canvas scene version is not supported. Keep the last valid scene and update SiteForge."
        case .emptyScene: "The canvas scene has no renderable root. Keep the last valid scene and inspect the project."
        case .duplicateObject, .duplicatePaintOrder, .invalidObject:
            "The canvas scene is internally inconsistent. The last valid scene remains displayed."
        case .objectLimitExceeded, .tileLimitExceeded, .rasterLimitExceeded, .cacheLimitExceeded:
            "The canvas exceeds a safe rendering limit. Reduce visible content or zoom out."
        case .cancelled: "Canvas rendering was cancelled. The last valid scene remains displayed."
        case .staleResult: "A newer canvas scene superseded this render."
        }
    }
}

enum CanvasRendererPolicy {
    static let maximumObjects = ResolvedGraphPolicy.maximumNodes
    static let tileDevicePixels = 512
    static let maximumTiles = 512
    static let maximumRasterDimension = 32_768.0
    static let maximumCacheBytes = 96 * 1_024 * 1_024
    static let maximumRetainedGenerations = 2
    static let maximumAccessibilityElements = 256
    static let cancellationStride = 64
}

struct CanvasRenderCancellation: Sendable {
    let isCancelled: @Sendable (Int) -> Bool
    static let never = CanvasRenderCancellation(isCancelled: { _ in false })
}

struct CanvasRendererCore: Sendable {
    static let requirementIDs: Set<String> = [
        "SF-0407-001", "SF-0407-002", "SF-0407-003", "SF-0407-004",
        "SF-0407-005", "SF-0407-006", "SF-0407-007", "SF-0407-008",
    ]

    func prepare(
        scene: CanvasRenderSceneSnapshot,
        overlays: CanvasEditorOverlaySnapshot,
        viewport: CanvasViewportState,
        previous: CanvasRenderSceneSnapshot? = nil,
        cancellation: CanvasRenderCancellation = .never
    ) throws -> CanvasRenderPlan {
        try validate(scene, overlays: overlays, cancellation: cancellation)
        let transform = viewport.transform
        let visible = viewport.visibleWorldRect
        let painted = scene.objects.sorted {
            $0.paintOrder == $1.paintOrder ? $0.id.description < $1.id.description : $0.paintOrder < $1.paintOrder
        }
        let invalidation = invalidation(previous: previous, next: scene)
        let dirty = dirtyRegions(previous: previous, next: scene, invalidation: invalidation)
        let tiles = try buildTiles(objects: scene.pageBackground.map { [$0] + painted } ?? painted,
                                  viewport: viewport, cancellation: cancellation)
        var accessibility: [CanvasAccessibilityElementSnapshot] = []
        accessibility.reserveCapacity(min(CanvasRendererPolicy.maximumAccessibilityElements, painted.count))
        for object in painted where accessibility.count < CanvasRendererPolicy.maximumAccessibilityElements {
            guard object.isVisible,
                  let visibleFrame = clippedFrame(object.frame, to: object.clipRect, visibleWithin: visible) else {
                continue
            }
            let origin = try transform.worldToViewport(visibleFrame.origin)
            accessibility.append(CanvasAccessibilityElementSnapshot(
                id: accessibilityID(for: object.id),
                objectID: object.id,
                label: object.accessibilityLabel,
                help: object.accessibilityHelp,
                frame: ViewportRect(
                    origin: origin,
                    size: ViewportSize(
                        width: visibleFrame.size.width * viewport.zoom.value,
                        height: visibleFrame.size.height * viewport.zoom.value
                    )
                ),
                paintOrder: object.paintOrder,
                textContent: object.plainText
            ))
        }
        return CanvasRenderPlan(
            identity: scene.identity,
            surfaceID: scene.surfaceID,
            viewport: viewport,
            authoredObjects: painted,
            pageBackground: scene.pageBackground,
            tiles: tiles,
            accessibilityElements: accessibility,
            dirtyWorldRegions: dirty,
            invalidation: invalidation,
            deterministicDigest: digest(scene.paintObjects)
        )
    }

    func hitTest(_ point: WorldPoint, in plan: CanvasRenderPlan) -> NodeID? {
        hitTest(point, in: plan, eligibleIDs: nil)
    }

    func hitTest(_ point: WorldPoint, in plan: CanvasRenderPlan, eligibleIDs: Set<NodeID>?) -> NodeID? {
        plan.authoredObjects.reversed().first { object in
            (eligibleIDs?.contains(object.id) ?? true)
                && object.isVisible
                && contains(object.frame, point)
                && isInsideClip(object, point: point)
        }?.id
    }

    func previewSnapshot(from scene: CanvasRenderSceneSnapshot) -> CanvasPreviewSceneSnapshot {
        CanvasPreviewSceneSnapshot(
            documentID: scene.identity.documentID,
            revision: scene.identity.revision,
            objects: scene.objects,
            deterministicDigest: digest(scene.paintObjects),
            pageBackground: scene.pageBackground
        )
    }

    private func validate(
        _ scene: CanvasRenderSceneSnapshot,
        overlays: CanvasEditorOverlaySnapshot,
        cancellation: CanvasRenderCancellation
    ) throws {
        guard scene.schemaVersion == CanvasRenderSceneSnapshot.currentSchemaVersion else {
            throw CanvasRendererError.unsupportedSchema(scene.schemaVersion)
        }
        // An empty scene is a valid, explicit blank-project state. Keeping it
        // renderable means the canvas can adopt a real empty plan rather than
        // retaining a stale scene or fabricating a root-node rectangle.
        guard scene.paintObjects.count <= CanvasRendererPolicy.maximumObjects else {
            throw CanvasRendererError.objectLimitExceeded(scene.paintObjects.count)
        }
        guard overlays.identity == scene.identity else { throw CanvasRendererError.staleResult }
        var ids = Set<NodeID>()
        var orders = Set<Int>()
        for (index, object) in scene.paintObjects.enumerated() {
            if index.isMultiple(of: CanvasRendererPolicy.cancellationStride), cancellation.isCancelled(index) {
                throw CanvasRendererError.cancelled
            }
            guard ids.insert(object.id).inserted else { throw CanvasRendererError.duplicateObject(object.id) }
            guard orders.insert(object.paintOrder).inserted else {
                throw CanvasRendererError.duplicatePaintOrder(object.paintOrder)
            }
            guard object.frame.isValid, object.frame.size.width <= CanvasRendererPolicy.maximumRasterDimension,
                  object.frame.size.height <= CanvasRendererPolicy.maximumRasterDimension,
                  object.clipRect?.isValid != false, !object.accessibilityLabel.isEmpty,
                  object.opacity.isFinite, (0...1).contains(object.opacity),
                  object.cornerRadius.isFinite, object.cornerRadius >= 0,
                  object.border?.isValid != false, object.shadow?.isValid != false,
                  (object.fillRGBA == nil || (object.fillRGBA?.count == 4 && object.fillRGBA!.allSatisfy({ $0.isFinite && (0...1).contains($0) }))),
                  object.fillLayers.allSatisfy(\.isValid) else {
                throw CanvasRendererError.invalidObject(object.id)
            }
        }
        guard !cancellation.isCancelled(scene.paintObjects.count) else { throw CanvasRendererError.cancelled }
    }

    private func buildTiles(
        objects: [CanvasRenderObject],
        viewport: CanvasViewportState,
        cancellation: CanvasRenderCancellation
    ) throws -> [CanvasRenderTile] {
        let scale = viewport.pixelRatio.value
        let width = viewport.viewportSize.width * scale
        let height = viewport.viewportSize.height * scale
        guard width <= CanvasRendererPolicy.maximumRasterDimension,
              height <= CanvasRendererPolicy.maximumRasterDimension else { throw CanvasRendererError.rasterLimitExceeded }
        let columns = max(1, Int(ceil(width / Double(CanvasRendererPolicy.tileDevicePixels))))
        let rows = max(1, Int(ceil(height / Double(CanvasRendererPolicy.tileDevicePixels))))
        guard columns * rows <= CanvasRendererPolicy.maximumTiles else {
            throw CanvasRendererError.tileLimitExceeded(columns * rows)
        }
        var tiles: [CanvasRenderTile] = []
        tiles.reserveCapacity(columns * rows)
        let transform = viewport.transform
        for row in 0..<rows {
            for column in 0..<columns {
                let x = Double(column * CanvasRendererPolicy.tileDevicePixels)
                let y = Double(row * CanvasRendererPolicy.tileDevicePixels)
                let tileWidth = min(Double(CanvasRendererPolicy.tileDevicePixels), width - x)
                let tileHeight = min(Double(CanvasRendererPolicy.tileDevicePixels), height - y)
                let device = DeviceRect(origin: DevicePoint(x: x, y: y), size: DeviceSize(width: tileWidth, height: tileHeight))
                let viewportOrigin = try transform.deviceToViewport(device.origin)
                let worldOrigin = try transform.viewportToWorld(viewportOrigin)
                let worldFrame = WorldRect(
                    origin: worldOrigin,
                    size: WorldSize(
                        width: tileWidth / scale / viewport.zoom.value,
                        height: tileHeight / scale / viewport.zoom.value
                    )
                )
                let objectIDs = objects.filter {
                    $0.isVisible && intersects(rasterBounds(for: $0), worldFrame) && isInsideClip($0)
                }.map(\.id)
                let bytes = Int(tileWidth * tileHeight * 4)
                tiles.append(CanvasRenderTile(
                    id: CanvasRenderTileID(column: column, row: row),
                    deviceFrame: device,
                    objectIDs: objectIDs,
                    estimatedBytes: bytes
                ))
            }
        }
        let total = tiles.reduce(0) { $0 + $1.estimatedBytes }
        guard total <= CanvasRendererPolicy.maximumCacheBytes else { throw CanvasRendererError.cacheLimitExceeded }
        return tiles
    }

    /// Shadows expand raster adoption and invalidation only. Canonical,
    /// selection, hit-test, Inspector, and accessibility geometry remains the
    /// authored object frame.
    private func rasterBounds(for object: CanvasRenderObject) -> WorldRect {
        guard let shadow = object.shadow else { return object.frame }
        let expansion = shadow.blur + shadow.spread
        let minimumX = min(object.frame.minX, object.frame.minX + shadow.offsetX) - expansion
        let minimumY = min(object.frame.minY, object.frame.minY + shadow.offsetY) - expansion
        let maximumX = max(object.frame.maxX, object.frame.maxX + shadow.offsetX) + expansion
        let maximumY = max(object.frame.maxY, object.frame.maxY + shadow.offsetY) + expansion
        return WorldRect(
            origin: WorldPoint(x: minimumX, y: minimumY),
            size: WorldSize(width: maximumX - minimumX, height: maximumY - minimumY)
        )
    }

    private func invalidation(previous: CanvasRenderSceneSnapshot?, next: CanvasRenderSceneSnapshot) -> CanvasInvalidationKind {
        guard let previous else { return .initial }
        guard previous.identity.documentID == next.identity.documentID,
              previous.identity.sceneID == next.identity.sceneID,
              previous.identity.scale == next.identity.scale else { return .fullRaster }
        return previous.paintObjects == next.paintObjects ? .compositorOnly : .dirtyRegions
    }

    private func dirtyRegions(
        previous: CanvasRenderSceneSnapshot?,
        next: CanvasRenderSceneSnapshot,
        invalidation: CanvasInvalidationKind
    ) -> [WorldRect] {
        guard invalidation == .dirtyRegions, let previous else {
            return invalidation == .compositorOnly ? [] : next.paintObjects.map { rasterBounds(for: $0) }
        }
        let old = Dictionary(uniqueKeysWithValues: previous.paintObjects.map { ($0.id, $0) })
        let new = Dictionary(uniqueKeysWithValues: next.paintObjects.map { ($0.id, $0) })
        return Set(old.keys).union(new.keys).sorted { $0.description < $1.description }.flatMap { id -> [WorldRect] in
            guard old[id] != new[id] else { return [] }
            return [old[id], new[id]].compactMap { $0 }.map { rasterBounds(for: $0) }
        }
    }

    private func contains(_ rect: WorldRect, _ point: WorldPoint) -> Bool {
        point.x >= rect.minX && point.y >= rect.minY && point.x <= rect.maxX && point.y <= rect.maxY
    }

    private func intersects(_ lhs: WorldRect, _ rhs: WorldRect) -> Bool {
        lhs.minX < rhs.maxX && lhs.maxX > rhs.minX && lhs.minY < rhs.maxY && lhs.maxY > rhs.minY
    }

    /// Accessibility geometry represents the pixels a user can actually
    /// reach in this viewport generation. Exposing the authored frame here
    /// would place VoiceOver targets over clipped ancestors or offscreen
    /// pasteboard even though those pixels cannot be seen or hit-tested.
    private func clippedFrame(
        _ frame: WorldRect,
        to clip: WorldRect?,
        visibleWithin visible: WorldRect
    ) -> WorldRect? {
        let minX = max(max(frame.minX, clip?.minX ?? frame.minX), visible.minX)
        let minY = max(max(frame.minY, clip?.minY ?? frame.minY), visible.minY)
        let maxX = min(min(frame.maxX, clip?.maxX ?? frame.maxX), visible.maxX)
        let maxY = min(min(frame.maxY, clip?.maxY ?? frame.maxY), visible.maxY)
        guard maxX > minX, maxY > minY else { return nil }
        return WorldRect(
            origin: WorldPoint(x: minX, y: minY),
            size: WorldSize(width: maxX - minX, height: maxY - minY)
        )
    }

    private func isInsideClip(_ object: CanvasRenderObject, point: WorldPoint? = nil) -> Bool {
        guard let clip = object.clipRect else { return true }
        return point.map { contains(clip, $0) } ?? intersects(object.frame, clip)
    }

    private func accessibilityID(for id: NodeID) -> CanvasAccessibilityID {
        CanvasAccessibilityID(id.rawValue)
    }

    private func digest(_ objects: [CanvasRenderObject]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(objects.sorted {
            $0.paintOrder == $1.paintOrder ? $0.id.description < $1.id.description : $0.paintOrder < $1.paintOrder
        })) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct CanvasRenderAdoptionGate: Sendable {
    func validate(_ plan: CanvasRenderPlan, expected: CanvasRenderRequestIdentity) throws {
        guard plan.identity == expected else { throw CanvasRendererError.staleResult }
    }
}

struct CanvasRenderDisplayState: Sendable {
    private(set) var lastValidPlan: CanvasRenderPlan?

    mutating func adopt(_ plan: CanvasRenderPlan, expected: CanvasRenderRequestIdentity) throws {
        try CanvasRenderAdoptionGate().validate(plan, expected: expected)
        lastValidPlan = plan
    }
}

actor CanvasRenderWorker {
    private let core = CanvasRendererCore()
    func prepare(
        scene: CanvasRenderSceneSnapshot,
        overlays: CanvasEditorOverlaySnapshot,
        viewport: CanvasViewportState,
        previous: CanvasRenderSceneSnapshot? = nil
    ) throws -> CanvasRenderPlan {
        try core.prepare(
            scene: scene,
            overlays: overlays,
            viewport: viewport,
            previous: previous,
            cancellation: CanvasRenderCancellation { _ in Task<Never, Never>.isCancelled }
        )
    }
}

struct CanvasRenderCache: Sendable {
    private(set) var entries: [CanvasRenderRequestIdentity: [CanvasRenderTile]] = [:]
    private(set) var order: [CanvasRenderRequestIdentity] = []

    mutating func insert(_ plan: CanvasRenderPlan) {
        entries[plan.identity] = plan.tiles
        order.removeAll { $0 == plan.identity }
        order.append(plan.identity)
        while order.count > CanvasRendererPolicy.maximumRetainedGenerations {
            let evicted = order.removeFirst()
            entries.removeValue(forKey: evicted)
        }
    }
}

enum CanvasRenderDiagnosticResult: String, Codable, Sendable { case success, failure, cancelled, stale }
struct CanvasRenderDiagnosticRecord: Codable, Equatable, Sendable {
    let requirementID: String
    let operation: String
    let surfaceIdentifier: String
    let generation: UInt64
    let durationMilliseconds: Double
    let invalidation: CanvasInvalidationKind?
    let tileCount: Int
    let cacheBytes: Int
    let frameCount: Int
    let stallCount: Int
    let result: CanvasRenderDiagnosticResult
    let failureCategory: String?
}

actor CanvasRenderDiagnostics {
    private var buffer: BoundedDiagnosticBuffer<CanvasRenderDiagnosticRecord>

    init(capacity: Int = DiagnosticRetentionPolicy.defaultCapacity) {
        buffer = BoundedDiagnosticBuffer(capacity: capacity)
    }

    func append(_ record: CanvasRenderDiagnosticRecord) { buffer.append(record) }
    func snapshot() -> [CanvasRenderDiagnosticRecord] { buffer.snapshot() }
    func droppedRecordCount() -> UInt64 { buffer.droppedRecordCount }
}

enum CanvasRenderDiagnosticFactory {
    static func make(
        operation: String,
        plan: CanvasRenderPlan?,
        identity: CanvasRenderRequestIdentity,
        surfaceID: CanvasRenderSurfaceID,
        durationMilliseconds: Double,
        result: CanvasRenderDiagnosticResult,
        failureCategory: String? = nil
    ) -> CanvasRenderDiagnosticRecord {
        let tiles = plan?.tiles ?? []
        return CanvasRenderDiagnosticRecord(
            requirementID: "SF-0407-008",
            operation: operation,
            surfaceIdentifier: DiagnosticStableIdentifier.sanitize(
                surfaceID.description,
                domain: .canvasRender,
                kind: "surface"
            ),
            generation: identity.viewportGeneration,
            durationMilliseconds: max(0, durationMilliseconds),
            invalidation: plan?.invalidation,
            tileCount: tiles.count,
            cacheBytes: tiles.reduce(0) { $0 + $1.estimatedBytes },
            frameCount: 0,
            stallCount: 0,
            result: result,
            failureCategory: failureCategory.map {
                DiagnosticErrorCategory.closedCategory(forUntrustedValue: $0).rawValue
            }
        )
    }
}
