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
    var isValid: Bool { rgba.count == 4 && rgba.allSatisfy { $0.isFinite && (0...1).contains($0) } && width.isFinite && width >= 0 && width <= 100 }
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
        gradientLine(angleDegrees: angleDegrees, width: 1, height: 1)
    }

    /// CSS magic-corner geometry in physical box coordinates. Scaling a
    /// unit-square direction changes its angle on rectangular boxes.
    static func gradientLine(angleDegrees: Double, width: Double, height: Double) -> (start: (x: Double, y: Double), end: (x: Double, y: Double)) {
        let radians = angleDegrees * .pi / 180
        let dx = cos(radians), dy = sin(radians)
        let length = abs(dx) * width + abs(dy) * height
        return (start: (width / 2 - dx * length / 2, height / 2 - dy * length / 2),
                end: (width / 2 + dx * length / 2, height / 2 + dy * length / 2))
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
            return gradientRGBA(orderedStops: ordered, at: projection)
        }
    }

    static func gradientRGBA(orderedStops: [CanvasGradientStop], at position: Double) -> [Double]? {
        guard position.isFinite, let first = orderedStops.first, let last = orderedStops.last else { return nil }
        if position < first.position { return first.rgba }
        if position >= last.position { return last.rgba }
        for pair in zip(orderedStops, orderedStops.dropFirst()) where position < pair.1.position {
            let span = pair.1.position - pair.0.position
            guard span > 0 else { continue }
            let a = pair.0.rgba, b = pair.1.rgba
            guard a.count == 4, b.count == 4,
                  let color = CanonicalSolidColor.premultipliedInterpolation(
                    .init(red: a[0], green: a[1], blue: a[2], alpha: a[3]),
                    .init(red: b[0], green: b[1], blue: b[2], alpha: b[3]), fraction: (position - pair.0.position) / span) else { return nil }
            return [color.red, color.green, color.blue, color.alpha]
        }
        return last.rgba
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
    let imageIsPixelated: Bool?
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
        imageIsPixelated: Bool? = nil,
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
        self.imageIsPixelated = imageIsPixelated
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
    var isPixelated = false
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
    /// OD-045 / SF-0803: present only for an Image in media mode.
    var media: InternalStaticMedia? = nil
}

/// OD-045 / SF-0803: the playable file behind an Image in media mode. Paths
/// come only from the verified content-addressed export plan.
struct InternalStaticMedia: Equatable, Sendable {
    let assetID: AssetID
    let kind: MediaAssetKind
    let mediaType: String
    let outputPath: String?
    let captionsPath: String?
    let captionsLanguage: String?
    let captionsLabel: String?
    let loops: Bool
    let isMuted: Bool
    let autoplays: Bool
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
        viewportWidth: Double? = nil,
        mediaAssets: [AssetID: MediaAsset] = [:],
        mediaOutputPaths: [AssetID: String] = [:]
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
                image: staticImage(for: node, outputPaths: imageOutputPaths, assets: imageAssets,
                                   media: mediaAssets, mediaPaths: mediaOutputPaths),
                imageFill: staticImageFill(for: node, outputPaths: imageOutputPaths),
                fillLayers: staticFillLayers(for: node, colorTokens: colorTokens),
                opacity: staticOpacity(for: node),
                boxStyle: staticBoxStyle(for: node, colorTokens: colorTokens, reusableStyleIndex: reusableStyleIndex),
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
        assets: [AssetID: ImageAsset],
        media: [AssetID: MediaAsset] = [:],
        mediaPaths: [AssetID: String] = [:]
    ) -> InternalStaticImage? {
        guard let style = CanonicalImageStyle.resolve(node) else { return nil }
        let asset = assets[style.assetID]
        let hasSafeDimensions = asset.map {
            (1...ImageAsset.maximumPixelDimension).contains($0.pixelWidth) &&
            (1...ImageAsset.maximumPixelDimension).contains($0.pixelHeight)
        } == true
        return .init(
            isPixelated: (try? CanonicalQRCode.resolve(node)) != nil,
            assetID: style.assetID,
            outputPath: outputPaths[style.assetID],
            intrinsicWidth: hasSafeDimensions ? asset?.pixelWidth : nil,
            intrinsicHeight: hasSafeDimensions ? asset?.pixelHeight : nil,
            altText: style.altText,
            isDecorative: style.isDecorative,
            fitMode: style.fitMode,
            focalX: style.focalX,
            focalY: style.focalY,
            media: staticMedia(for: node, media: media, paths: mediaPaths)
        )
    }

    /// OD-045 / SF-0803: nil keeps the plain Image (no media mode, or the
    /// file's facts are unavailable). Autoplay survives only for muted video.
    private static func staticMedia(for node: DocumentNode, media: [AssetID: MediaAsset],
                                    paths: [AssetID: String]) -> InternalStaticMedia? {
        guard let playback = CanonicalMediaPlayback.resolve(node), let asset = media[playback.assetID],
              asset.kind != .captions else { return nil }
        let captions = asset.kind == .video ? playback.captionsAssetID.flatMap { media[$0] } : nil
        return .init(assetID: asset.id, kind: asset.kind, mediaType: asset.format.mediaType, outputPath: paths[asset.id],
                     captionsPath: captions.flatMap { paths[$0.id] }, captionsLanguage: captions?.language,
                     captionsLabel: captions?.displayName, loops: playback.loops, isMuted: playback.isMuted,
                     autoplays: asset.kind == .video && playback.autoplays && playback.isMuted)
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
        guard DesignInspectorCommandRegistry.fillKinds.contains(node.kind) else { return [] }
        return LocalColorTokenResolver.resolvedLayers(for: node, tokens: colorTokens)
    }

    private static func staticOpacity(for node: DocumentNode) -> Double? {
        guard DesignBoxStyleCommandRegistry.applicableKinds.contains(node.kind),
              let value = node.insertionNumberProperty("style.opacity"),
              value.isFinite, (0...1).contains(value) else { return nil }
        return value
    }

    /// SF-0510-003, SF-1204-003: the same resolution as the canvas, so linked
    /// border/corners/shadow export exactly as authored. `nil` index (callers
    /// that only need structure) keeps object-only values.
    private static func staticBoxStyle(for node: DocumentNode, colorTokens: [LocalColorToken],
                                       reusableStyleIndex: CanonicalReusableStyleIndex?) -> CanonicalBoxStyle? {
        guard DesignBoxStyleCommandRegistry.applicableKinds.contains(node.kind),
              DesignBoxStyleCommandRegistry.hasWellFormedContentBoxProperties(node) else { return nil }
        return LocalColorTokenResolver.resolvedBoxStyle(for: node, tokens: colorTokens, reusableStyles: reusableStyleIndex)
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
    /// `fontFallbacks` (SF-0805): lowercased project family → fallback stack.
    static func emit(nodes: [InternalRenderTreeNode], fontFallbacks: [String: String] = [:]) -> String {
        nodes.filter { $0.typography != nil }
            .sorted { $0.id.description < $1.id.description }
            .compactMap { rule(for: $0, fontFallbacks: fontFallbacks) }
            .joined(separator: "\n")
    }

    private static func rule(for node: InternalRenderTreeNode, fontFallbacks: [String: String]) -> String? {
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
            declarations.insert("font-family: \"\(family)\", \(fontFallbacks[style.family.lowercased()] ?? "system-ui");", at: 0)
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
        return "\(node.cssSelector) { object-fit: \(fit); object-position: \(focal);\(image.isPixelated ? " image-rendering:pixelated;" : "") }"
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
            // Fixed geometry already establishes absolute placement. Only an
            // authored positioning mode may replace it with static flow.
            var declarations: [String] = []
            if positioning.origin == .authored || positioning.mode != .static {
                declarations.append("position: \(positioning.mode.rawValue);")
            }
            for (name, value) in [
                ("top", positioning.top), ("right", positioning.right),
                ("bottom", positioning.bottom), ("left", positioning.left),
            ] where value != nil {
                declarations.append("\(name): \(number(value!))px;")
            }
            if positioning.zIndex != 0 { declarations.append("z-index: \(positioning.zIndex);") }
            if !declarations.isEmpty { output.append("\(node.cssSelector) { \(declarations.joined(separator: " ")) }") }
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
                   path.range(of: "^assets/[a-f0-9]{64}\\.(png|jpg|svg)$", options: .regularExpression) != nil {
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
    /// OD-042 zip adapter: the plan is over the ZIP32 limits (65,535 files or 4 GiB).
    case archiveTooLarge
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
            // SF-1206-004 (ADR-0121): read every staged file back before promotion,
            // so a short or changed write never replaces the destination.
            for file in plan.files {
                try cancellation.check()
                guard try Data(contentsOf: safeOutputURL(path: file.path, root: stage)) == Data(file.contents.utf8) else {
                    throw LocalStaticBuildWriteError.writeFailed
                }
            }
            for file in plan.binaryFiles {
                try cancellation.check()
                guard try Data(contentsOf: safeOutputURL(path: file.path, root: stage)) == file.contents else {
                    throw LocalStaticBuildWriteError.writeFailed
                }
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

// MARK: - OD-042 export targets (SF-1209)

/// The same immutable build plan can be delivered as a folder or as one zip
/// archive. Both carry byte-identical files; only the container differs.
enum StaticExportTarget: String, CaseIterable, Identifiable, Sendable {
    case folder, zipArchive
    var id: String { rawValue }
    var title: String {
        switch self {
        case .folder: "Folder"
        case .zipArchive: "Zip Archive"
        }
    }

    /// SF-1209-003 (ADR-0145): the adapter contract. A target that cannot carry
    /// a plan says why before anything is written; the writer enforces the same
    /// rule, so the check and the write never disagree.
    func unsupportedReason(for plan: LocalStaticBuildPlan) -> String? {
        switch self {
        case .folder:
            return nil
        case .zipArchive:
            return StaticSiteZipArchive.canArchive(plan) ? nil
                : "This website has more than 65,535 files or 4 GB, the most one zip archive can hold. Export it as a folder instead."
        }
    }
}

/// SF-1209-001/008 (ADR-0145): a value-free record of one export. It names the
/// target, a sanitized document token, the revision and file count, never a
/// destination path, file name or file contents.
struct StaticExportDiagnostic: Equatable, Sendable {
    let requirementID: String
    let operation: String
    let target: StaticExportTarget
    let documentToken: String
    let revision: UInt64
    let fileCount: Int
    let durationMilliseconds: Int
    let failureCategory: String

    init(target: StaticExportTarget, documentID: DocumentID, plan: LocalStaticBuildPlan,
         duration: Duration, failure: LocalStaticBuildWriteError?) {
        requirementID = "SF-1209-008"
        operation = "export"
        self.target = target
        documentToken = DiagnosticStableIdentifier.sanitize(documentID.description, domain: .staticBuild, kind: "document")
        revision = plan.revision
        fileCount = plan.files.count + plan.binaryFiles.count
        let parts = duration.components
        durationMilliseconds = max(0, Int(parts.seconds) * 1_000 + Int(parts.attoseconds / 1_000_000_000_000_000))
        failureCategory = failure?.diagnosticCategory ?? "none"
    }
}

extension LocalStaticBuildWriteError {
    /// Closed, value-free category for export diagnostics (SF-1209-008).
    var diagnosticCategory: String {
        switch self {
        case .unsafeDestination: "unsafe-destination"
        case .destinationExists: "destination-exists"
        case .stale: "stale"
        case .cancelled: "cancelled"
        case .insufficientSpace: "insufficient-space"
        case .permissionDenied: "permission-denied"
        case .writeFailed: "write-failed"
        case .archiveTooLarge: "archive-too-large"
        }
    }
}

/// Deterministic ZIP (PKWARE APPNOTE) with stored entries only, so the same
/// plan always produces the same bytes: entries sorted by path, UTF-8 names,
/// DOS epoch timestamps (1980-01-01 00:00), regular-file permissions 0644, no
/// extra fields or comments. ZIP64 is not written; a plan over the ZIP32
/// limits is refused before anything is written.
enum StaticSiteZipArchive {
    enum ArchiveError: Error, Equatable, Sendable { case unsafePath, duplicatePath, tooLarge, malformed }
    struct Entry: Equatable, Sendable { let path: String; let data: Data }

    static let maximumEntryCount = Int(UInt16.max)
    static let maximumByteCount = Int(UInt32.max)
    private static let localHeaderSignature: UInt32 = 0x0403_4B50
    private static let centralHeaderSignature: UInt32 = 0x0201_4B50
    private static let endSignature: UInt32 = 0x0605_4B50
    private static let versionNeeded: UInt16 = 20
    private static let versionMadeBy: UInt16 = 0x0314 // UNIX host, specification 2.0
    private static let utf8NamesFlag: UInt16 = 0x0800
    private static let dosEpochDate: UInt16 = 0x0021 // 1980-01-01
    private static let regularFileAttributes: UInt32 = 0o100644 << 16

    /// The exact size `archive(_:)` would produce, computed without building
    /// it: each entry has a 30-byte local header and a 46-byte central header,
    /// both carrying the name, plus its data; the archive ends with 22 bytes.
    static func archivedByteCount(_ plan: LocalStaticBuildPlan) -> Int {
        let names = plan.files.map(\.path.utf8.count) + plan.binaryFiles.map(\.path.utf8.count)
        let data = plan.files.reduce(0) { $0 + $1.contents.utf8.count } + plan.binaryFiles.reduce(0) { $0 + $1.contents.count }
        return names.reduce(0) { $0 + 76 + 2 * $1 } + data + 22
    }

    /// SF-1209-003: true when the plan fits the ZIP32 limits this writer uses.
    static func canArchive(_ plan: LocalStaticBuildPlan) -> Bool {
        let names = plan.files.map(\.path.utf8.count) + plan.binaryFiles.map(\.path.utf8.count)
        return names.count <= maximumEntryCount && (names.max() ?? 0) <= Int(UInt16.max)
            && archivedByteCount(plan) <= maximumByteCount
    }

    /// Same rules as the folder writer: relative, no empty, `.` or `..`
    /// components, no backslash or NUL.
    static func isSafeEntryPath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\u{0}") else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    static func archive(_ plan: LocalStaticBuildPlan,
                        cancellation: CooperativeCancellationCheckpoint = .init()) throws -> Data {
        let textEntries = plan.files.map { Entry(path: $0.path, data: Data($0.contents.utf8)) }
        let binaryEntries = plan.binaryFiles.map { Entry(path: $0.path, data: $0.contents) }
        let entries = (textEntries + binaryEntries).sorted { $0.path < $1.path }
        guard entries.count <= maximumEntryCount else { throw ArchiveError.tooLarge }
        var seen = Set<String>()
        for entry in entries {
            guard isSafeEntryPath(entry.path) else { throw ArchiveError.unsafePath }
            guard seen.insert(entry.path).inserted else { throw ArchiveError.duplicatePath }
        }
        var output = Data()
        var central = Data()
        for entry in entries {
            try cancellation.check()
            let name = Data(entry.path.utf8)
            guard name.count <= Int(UInt16.max),
                  output.count + 30 + name.count + entry.data.count <= maximumByteCount else {
                throw ArchiveError.tooLarge
            }
            let offset = UInt32(output.count)
            let size = UInt32(entry.data.count)
            let checksum = crc32(entry.data)

            output.appendZipValue(localHeaderSignature)
            output.appendZipValue(versionNeeded)
            output.appendZipValue(utf8NamesFlag)
            output.appendZipValue(UInt16(0))             // method: stored
            output.appendZipValue(UInt16(0))             // time 00:00:00
            output.appendZipValue(dosEpochDate)
            output.appendZipValue(checksum)
            output.appendZipValue(size)                  // compressed size
            output.appendZipValue(size)                  // uncompressed size
            output.appendZipValue(UInt16(name.count))
            output.appendZipValue(UInt16(0))             // extra field length
            output.append(name)
            output.append(entry.data)

            central.appendZipValue(centralHeaderSignature)
            central.appendZipValue(versionMadeBy)
            central.appendZipValue(versionNeeded)
            central.appendZipValue(utf8NamesFlag)
            central.appendZipValue(UInt16(0))            // method: stored
            central.appendZipValue(UInt16(0))            // time
            central.appendZipValue(dosEpochDate)
            central.appendZipValue(checksum)
            central.appendZipValue(size)
            central.appendZipValue(size)
            central.appendZipValue(UInt16(name.count))
            central.appendZipValue(UInt16(0))            // extra field length
            central.appendZipValue(UInt16(0))            // comment length
            central.appendZipValue(UInt16(0))            // disk number start
            central.appendZipValue(UInt16(0))            // internal attributes
            central.appendZipValue(regularFileAttributes)
            central.appendZipValue(offset)
            central.append(name)
        }
        guard output.count + central.count + 22 <= maximumByteCount else { throw ArchiveError.tooLarge }
        let centralOffset = UInt32(output.count)
        output.append(central)
        output.appendZipValue(endSignature)
        output.appendZipValue(UInt16(0))                 // this disk
        output.appendZipValue(UInt16(0))                 // disk with the central directory
        output.appendZipValue(UInt16(entries.count))
        output.appendZipValue(UInt16(entries.count))
        output.appendZipValue(UInt32(central.count))
        output.appendZipValue(centralOffset)
        output.appendZipValue(UInt16(0))                 // comment length
        return output
    }

    /// Reads an archive in this stored format back and checks every entry:
    /// signatures, the name in both headers, stored method, sizes and CRC-32.
    /// The writer uses it to verify a staged archive before promoting it.
    static func storedEntries(_ archive: Data) throws -> [Entry] {
        let bytes = [UInt8](archive)
        guard bytes.count >= 22 else { throw ArchiveError.malformed }
        let end = bytes.count - 22
        guard try read(UInt32.self, bytes, end) == endSignature,
              try read(UInt16.self, bytes, end + 20) == 0 else { throw ArchiveError.malformed }
        let count = Int(try read(UInt16.self, bytes, end + 10))
        let centralSize = Int(try read(UInt32.self, bytes, end + 12))
        var cursor = Int(try read(UInt32.self, bytes, end + 16))
        guard cursor + centralSize == end else { throw ArchiveError.malformed }
        var entries: [Entry] = []
        for _ in 0..<count {
            guard try read(UInt32.self, bytes, cursor) == centralHeaderSignature,
                  try read(UInt16.self, bytes, cursor + 10) == 0 else { throw ArchiveError.malformed }
            let checksum = try read(UInt32.self, bytes, cursor + 16)
            let compressedSize = Int(try read(UInt32.self, bytes, cursor + 20))
            let size = Int(try read(UInt32.self, bytes, cursor + 24))
            let nameLength = Int(try read(UInt16.self, bytes, cursor + 28))
            let trailing = Int(try read(UInt16.self, bytes, cursor + 30)) + Int(try read(UInt16.self, bytes, cursor + 32))
            let local = Int(try read(UInt32.self, bytes, cursor + 42))
            let name = try slice(bytes, cursor + 46, nameLength)
            guard compressedSize == size,
                  try read(UInt32.self, bytes, local) == localHeaderSignature,
                  try read(UInt16.self, bytes, local + 8) == 0,
                  try read(UInt32.self, bytes, local + 14) == checksum,
                  Int(try read(UInt16.self, bytes, local + 26)) == nameLength,
                  try slice(bytes, local + 30, nameLength) == name,
                  let path = String(bytes: name, encoding: .utf8), isSafeEntryPath(path) else {
                throw ArchiveError.malformed
            }
            let dataStart = local + 30 + nameLength + Int(try read(UInt16.self, bytes, local + 28))
            guard dataStart + size <= end - centralSize else { throw ArchiveError.malformed }
            let data = Data(try slice(bytes, dataStart, size))
            guard crc32(data) == checksum else { throw ArchiveError.malformed }
            entries.append(.init(path: path, data: data))
            cursor += 46 + nameLength + trailing
        }
        guard cursor == end else { throw ArchiveError.malformed }
        return entries
    }

    /// CRC-32 (IEEE 802.3, reflected polynomial 0xEDB88320), as ZIP requires.
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = (value & 1) == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    private static func read<T: FixedWidthInteger & UnsignedInteger>(_ type: T.Type, _ bytes: [UInt8],
                                                                     _ offset: Int) throws -> T {
        let width = MemoryLayout<T>.size
        guard offset >= 0, offset <= bytes.count - width else { throw ArchiveError.malformed }
        var value: T = 0
        for index in 0..<width { value |= T(bytes[offset + index]) << (8 * index) }
        return value
    }

    private static func slice(_ bytes: [UInt8], _ offset: Int, _ length: Int) throws -> [UInt8] {
        guard offset >= 0, length >= 0, offset <= bytes.count - length else { throw ArchiveError.malformed }
        return Array(bytes[offset..<(offset + length)])
    }
}

private extension Data {
    mutating func appendZipValue<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}

extension LocalStaticBuildWriter {
    /// OD-042 zip adapter. Same revision, cancellation and destination rules
    /// as the folder writer. The archive is staged beside the destination, read
    /// back and verified, then promoted in one move; a failure leaves no
    /// partial archive and never changes an existing destination.
    static func writeZipArchive(_ plan: LocalStaticBuildPlan, to destination: URL, expectedRevision: UInt64,
                                replacingExisting: Bool = false, cancelled: Bool = false,
                                cancellation: CooperativeCancellationCheckpoint = .init()) throws {
        guard !cancelled, !Task.isCancelled else { throw LocalStaticBuildWriteError.cancelled }
        guard plan.revision == expectedRevision else { throw LocalStaticBuildWriteError.stale }
        let target = destination.standardizedFileURL
        guard target.path != "/", !target.path.isEmpty, target.pathExtension.lowercased() == "zip",
              (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw LocalStaticBuildWriteError.unsafeDestination
        }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory)
        // A zip never replaces a folder (or a package that looks like a file).
        guard !(exists && isDirectory.boolValue) else { throw LocalStaticBuildWriteError.unsafeDestination }
        guard !exists || replacingExisting else { throw LocalStaticBuildWriteError.destinationExists }
        // SF-1209-003: refuse an oversized plan before allocating the archive.
        guard StaticSiteZipArchive.canArchive(plan) else { throw LocalStaticBuildWriteError.archiveTooLarge }
        let archive: Data
        do {
            archive = try StaticSiteZipArchive.archive(plan, cancellation: cancellation)
        } catch is CancellationError {
            throw LocalStaticBuildWriteError.cancelled
        } catch StaticSiteZipArchive.ArchiveError.tooLarge {
            throw LocalStaticBuildWriteError.archiveTooLarge
        } catch {
            throw LocalStaticBuildWriteError.unsafeDestination
        }
        let stage = target.deletingLastPathComponent()
            .appendingPathComponent(".siteforge-build-\(UUID().uuidString).zip", isDirectory: false)
        do {
            try cancellation.check()
            try archive.write(to: stage, options: .withoutOverwriting)
            let staged = try Data(contentsOf: stage)
            guard staged == archive,
                  (try? StaticSiteZipArchive.storedEntries(staged))?.count == plan.files.count + plan.binaryFiles.count else {
                throw LocalStaticBuildWriteError.writeFailed
            }
            // Cancellation is observed again after staging, before promotion.
            try cancellation.check()
            if exists {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: stage, backupItemName: nil, options: [])
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
}

/// SF-0605, SF-1204-003: container queries in the static site. Each active
/// container gets `container-type: inline-size` and its name; each rule
/// becomes one `@container` block, in rule order after all other rules, so a
/// matching rule wins over base, fluid and breakpoint rules exactly as it does
/// on the canvas. Inactive containers and rules without a container emit nothing.
/// Lane V19: on a page without page flow the rules query the wrapper that
/// holds each queried container's contents (`StaticContainerQueryWrapping`;
/// the container's own line stays and is inert there, as no element is
/// inside it). `reusableStyles` gives a container the border of a linked
/// style, as `contentInset` does for the canvas.
enum StaticContainerQueryOutputEmitter {
    static func emit(pages: [DocumentPage], reusableStyles: CanonicalReusableStyleIndex? = nil) -> String {
        var containers: [String] = []
        var rules: [String] = []
        for page in pages {
            let nodesByID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
            let staticLayout = !page.usesConnectedOutput
            let unqueryable = StaticContainerQueryWrapping.unqueryableContainers(page)
            for node in page.nodes.sorted(by: { $0.id.description < $1.id.description }) {
                let selector = CanonicalCSSRule.selector(for: node.id)
                if CanonicalContainerQueries.isActiveContainer(node), let name = CanonicalContainerQueries.containerName(of: node) {
                    containers.append("\(selector) { container-type: inline-size; container-name: \(CanonicalContainerQueries.cssName(name)); }")
                }
                guard CanonicalContainerQueries.hasRules(node),
                      let nodeRules = try? CanonicalContainerQueries.rules(on: node) else { continue }
                var resolved: [(rule: CanonicalContainerQueryRule, container: DocumentNode, target: String)] = []
                for rule in nodeRules {
                    var ignored = Set<ContainerQueryFinding>()
                    guard let container = CanonicalContainerQueries.container(for: rule, of: node, nodesByID: nodesByID,
                                                                              findings: &ignored, unqueryable: unqueryable),
                          let containerName = CanonicalContainerQueries.containerName(of: container) else { continue }
                    // A named rule targets that container; an unnamed rule the
                    // nearest container, which is the one found above (on a
                    // page without page flow, the nearest wrapper).
                    resolved.append((rule, container, rule.container == nil ? "" : CanonicalContainerQueries.cssName(containerName) + " "))
                }
                // A page without page flow writes every object as its own
                // element, so a hiding rule names the object's contents too
                // (the canvas hides an object and everything inside it).
                let hiddenSelectors = (staticLayout ? StaticContainerQueryWrapping.subtree(of: node, nodesByID: nodesByID) : [node.id])
                    .map { CanonicalCSSRule.selector(for: $0) + "[data-siteforge-node]" }.joined(separator: ", ")
                for (index, entry) in resolved.enumerated() {
                    let condition = StaticContainerQueryWrapping.condition(entry.rule)
                    let declarations = entry.rule.values.compactMap {
                        CanonicalContainerQueries.cssDeclaration($0.key, $0.property.value)
                    }
                    if !declarations.isEmpty {
                        rules.append("@container \(entry.target)\(condition) { \(selector) { \(declarations.joined(separator: " ")) } }")
                    }
                    // Text and controls take `display` from compound selectors
                    // (`…[data-siteforge-node]`, `…:is(a,button)`), which a plain
                    // `display: none` loses to; hiding uses the node attribute's
                    // extra specificity, as connected-page output does. Show
                    // writes no `display` (lane V19): the object keeps its own
                    // (flex, grid, block), and a matching Show rule only stops
                    // hiding rules: a hide written here holds only while no
                    // later Show rule of the object matches (the later rule wins,
                    // as on the canvas), and `StaticVisibilityOutputEmitter`'s
                    // breakpoint hides hold only while no Show rule matches.
                    guard StaticContainerQueryWrapping.hiddenValue(entry.rule) == true else { continue }
                    let head = staticLayout
                        ? "@container \(StaticContainerQueryWrapping.uniqueName(entry.container.id)) \(condition)"
                        : "@container \(entry.target)\(condition)"
                    let cancels = resolved.suffix(from: index + 1).filter {
                        StaticContainerQueryWrapping.hiddenValue($0.rule) == false
                    }.map { later -> String in
                        let laterCondition = StaticContainerQueryWrapping.condition(later.rule)
                        return staticLayout
                            ? "@container \(StaticContainerQueryWrapping.uniqueName(later.container.id)) not (\(laterCondition))"
                            : "@container \(later.target)not (\(laterCondition))"
                    }
                    rules.append(StaticContainerQueryWrapping.nested([head] + cancels, "\(hiddenSelectors) { display: none; }"))
                }
            }
        }
        let wrappers = StaticContainerQueryWrapping.css(pages: pages, reusableStyles: reusableStyles)
        return (containers + wrappers + rules).joined(separator: "\n")
    }
}

// MARK: - SF-0606 responsive audit

/// One representative width the audit samples.
struct ResponsiveAuditSample: Hashable, Sendable {
    let breakpoint: ResponsiveBreakpoint
    let width: Double

    /// Desktop, Tablet and Mobile at their preset widths (matches `ViewportPreset`).
    static let standard: [ResponsiveAuditSample] = [
        .init(breakpoint: .desktop, width: 1_440), .init(breakpoint: .tablet, width: 768), .init(breakpoint: .mobile, width: 390),
    ]
}

enum ResponsiveAuditFindingKind: String, CaseIterable, Hashable, Sendable {
    case overflow
    case collision
    case truncation
    case tapTarget = "tap-target"
    case unreachableOverride = "unreachable-override"

    var title: String {
        switch self {
        case .overflow: "Outside the page"
        case .collision: "Overlapping content"
        case .truncation: "Text doesn't fit"
        case .tapTarget: "Small tap target"
        case .unreachableOverride: "Unused breakpoint setting"
        }
    }
}

/// SF-0606-001/003: one reproducible finding: what, where (stable identity),
/// at which width, with the measured numbers needed to verify a fix.
struct ResponsiveAuditFinding: Identifiable, Hashable, Sendable {
    let kind: ResponsiveAuditFindingKind
    let pageID: PageID
    let nodeID: NodeID
    /// The other object, for a collision.
    let otherNodeID: NodeID?
    let sample: ResponsiveAuditSample
    let bounds: WorldRect?
    /// Overflow in points, overlap area, needed text height, smallest side, or 0.
    let measure: Double
    let isSuppressed: Bool

    var id: String {
        [kind.rawValue, nodeID.description, otherNodeID?.description ?? "-", sample.breakpoint.rawValue,
         String(Int(sample.width))].joined(separator: ":")
    }

    var explanation: String {
        func points(_ value: Double) -> String { "\(Int(value.rounded())) pt" }
        let at = "at \(sample.breakpoint.title) (\(points(sample.width)) wide)"
        switch kind {
        case .overflow: return "Extends \(points(measure)) beyond the page \(at)."
        case .collision: return "Overlaps another text, image or control by \(points(measure.squareRoot())) square \(at)."
        case .truncation:
            return "Needs \(points(measure)) of height but has \(points(bounds?.size.height ?? 0)) \(at), so text is cut off."
        case .tapTarget:
            return "Its smallest side is \(points(measure)), below the \(points(CanonicalResponsiveAudit.minimumTapTarget)) minimum \(at)."
        case .unreachableOverride: return "Has its own size or layout setting \(at), but is hidden there, so the setting never shows."
        }
    }

    var repair: String {
        switch kind {
        case .overflow: return "Reduce its width or move it inside the page at this breakpoint, or let it fill its container."
        case .collision: return "Move or resize one of the two objects at this breakpoint, or place them in a Stack."
        case .truncation: return "Make the text box taller, use Hug height, or shorten the text."
        case .tapTarget: return "Make the button or link at least \(Int(CanonicalResponsiveAudit.minimumTapTarget)) pt in both directions."
        case .unreachableOverride: return "Show the object at this breakpoint, or remove its setting for this breakpoint."
        }
    }
}

struct ResponsiveAuditReport: Equatable, Sendable {
    let documentID: DocumentID
    let revision: UInt64
    let pageID: PageID
    let samples: [ResponsiveAuditSample]
    let findings: [ResponsiveAuditFinding]

    var activeFindings: [ResponsiveAuditFinding] { findings.filter { !$0.isSuppressed } }
    var suppressedCount: Int { findings.count - activeFindings.count }
}

/// SF-0606-003: the audit rules. Every check reads what the canvas draws at
/// the sampled width (the prepared scene and the page it was prepared from),
/// so a finding is exactly reproducible by opening that width.
enum CanonicalResponsiveAudit {
    static let requirementIDs: Set<String> = Set((1...8).map { String(format: "SF-0606-%03d", $0) })
    /// WCAG 2.2 SC 2.5.8 (Target Size, Minimum): 24 CSS px.
    static let minimumTapTarget = 24.0
    /// Collision checks compare at most this many content objects per parent.
    static let maximumObjectsPerParent = 400
    static let tolerance = 0.5

    /// Findings for one sample. `page` is the expanded page (container queries
    /// applied) the scene was prepared from; `canonicalPage` holds the stored
    /// objects (suppressions and breakpoint settings live there).
    static func findings(page: DocumentPage, canonicalPage: DocumentPage, objects: [CanvasRenderObject],
                         sample: ResponsiveAuditSample, checkpoint: () throws -> Void = {}) throws -> [ResponsiveAuditFinding] {
        let nodes = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let stored = Dictionary(uniqueKeysWithValues: canonicalPage.nodes.map { ($0.id, $0) })
        let chrome = Set(page.rootNodeIDs)
        func suppressed(_ kind: ResponsiveAuditFindingKind, _ id: NodeID) -> Bool {
            (stored[id] ?? nodes[id]).map { CanonicalResponsiveAuditSuppression.suppressedKinds(of: $0).contains(kind.rawValue) } ?? false
        }
        func finding(_ kind: ResponsiveAuditFindingKind, _ id: NodeID, other: NodeID? = nil, bounds: WorldRect?, _ measure: Double) -> ResponsiveAuditFinding {
            .init(kind: kind, pageID: canonicalPage.id, nodeID: id, otherNodeID: other, sample: sample, bounds: bounds,
                  measure: measure, isSuppressed: suppressed(kind, id) || other.map { suppressed(kind, $0) } == true)
        }
        let drawnFrames = Dictionary(objects.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
        // The scene's inherited clip always starts at the page bounds, so it
        // can never extend past them. Only ancestors that clip their content
        // (the same ancestors the scene uses) narrow what is shown; nil when
        // nothing of the object is shown.
        func shownHorizontalSpan(of object: CanvasRenderObject) -> (minX: Double, maxX: Double)? {
            var minX = object.frame.minX, maxX = object.frame.maxX
            var parent = nodes[object.id]?.parent
            var steps = 0
            while case .node(let id)? = parent, let ancestor = nodes[id], steps < nodes.count {
                steps += 1
                if DesignBoxStyleCommandRegistry.contentBoxKinds.contains(ancestor.kind),
                   DesignBoxStyleCommandRegistry.resolvedStyle(for: ancestor)?.clipsContent == true,
                   let clip = drawnFrames[id] {
                    minX = max(minX, clip.minX)
                    maxX = min(maxX, clip.maxX)
                }
                parent = ancestor.parent
            }
            return maxX > minX ? (minX, maxX) : nil
        }
        var result: [ResponsiveAuditFinding] = []
        let visible = objects.filter { $0.isVisible && !chrome.contains($0.id) && $0.pageFlowRole == nil }
        var contentByParent: [NodeID?: [CanvasRenderObject]] = [:]
        for object in visible {
            try checkpoint()
            let node = nodes[object.id]
            // Overflow: the visible part of the object beyond the page's sides.
            if let shown = shownHorizontalSpan(of: object) {
                let overflow = max(0, shown.maxX - sample.width, -shown.minX)
                if overflow > tolerance { result.append(finding(.overflow, object.id, bounds: object.frame, overflow)) }
            }
            // Tap targets: buttons and links.
            if node?.kind.isLinkControl == true || object.previewLink != nil {
                let side = min(object.frame.size.width, object.frame.size.height)
                if side + tolerance < minimumTapTarget { result.append(finding(.tapTarget, object.id, bounds: object.frame, side)) }
            }
            // Truncation: fixed-height text whose content needs more height.
            if let node, node.kind == .text, let text = object.plainText, !text.isEmpty,
               let typography = CanonicalTypography.resolved(for: node), typography.isValid,
               CanonicalSizingConstraints.effectiveMode(.height, node: node, breakpoint: sample.breakpoint, width: sample.width) != .hug {
                let needed = ResponsiveTextMetrics.height(text: text, width: object.frame.size.width, typography: typography)
                if needed > object.frame.size.height + 1 {
                    result.append(finding(.truncation, object.id, bounds: object.frame, needed))
                }
            }
            if object.plainText?.isEmpty == false || object.imageAssetID != nil || object.previewLink != nil {
                contentByParent[object.parentNodeID, default: []].append(object)
            }
        }
        // Collisions: content objects under the same parent that overlap.
        for (_, siblings) in contentByParent.sorted(by: { ($0.key?.description ?? "") < ($1.key?.description ?? "") }) {
            let bounded = Array(siblings.sorted { $0.id.description < $1.id.description }.prefix(maximumObjectsPerParent))
            for (offset, first) in bounded.enumerated() {
                try checkpoint()
                for second in bounded[(offset + 1)...] {
                    let width = min(first.frame.maxX, second.frame.maxX) - max(first.frame.minX, second.frame.minX)
                    let height = min(first.frame.maxY, second.frame.maxY) - max(first.frame.minY, second.frame.minY)
                    guard width > tolerance, height > tolerance else { continue }
                    result.append(finding(.collision, first.id, other: second.id, bounds: first.frame, width * height))
                }
            }
        }
        // Unused breakpoint settings: stored objects hidden at this breakpoint
        // that still carry their own size, position or layout for it.
        if sample.breakpoint != .desktop {
            let geometryPrefix = ResponsiveGeometryResolver.namespace + "." + sample.breakpoint.id.rawValue.uuidString.lowercased() + "."
            let containerPrefix = CanonicalResponsiveContainerNamespaceValidator.root + sample.breakpoint.id.rawValue.uuidString.lowercased() + "."
            for node in canonicalPage.canonicalDepthFirstNodes() {
                try checkpoint()
                guard ResponsiveVisibilityResolver.supports(node), !ResponsiveVisibilityResolver.isVisible(node, breakpoint: sample.breakpoint),
                      node.properties.contains(where: { $0.key.rawValue.hasPrefix(geometryPrefix) || $0.key.rawValue.hasPrefix(containerPrefix) })
                else { continue }
                result.append(finding(.unreachableOverride, node.id, bounds: nil, 0))
            }
        }
        return result.sorted { $0.id < $1.id }
    }
}

enum MultiPageStaticBuildError: Error, Equatable, Sendable { case invalidRoute, collision, invalidDocument }

/// SF-1107 (OD-041, ADR-0037): authored custom code placed verbatim in each
/// page. Site code comes first, then the page's own; CSS follows SiteForge's
/// stylesheet so authored rules can override it.
enum CustomCodeOutput {
    static func head(site: CustomCodeBlock?, page: CustomCodeBlock?) -> String {
        let html = [site?.headHTML, page?.headHTML].compactMap { $0 }
        let css = [site?.css, page?.css].compactMap { $0 }
        let style = css.isEmpty ? [] : ["<style data-siteforge-custom-code>\n" + css.joined(separator: "\n") + "\n</style>"]
        return (html + style).map { "\n" + $0 }.joined() + (html.isEmpty && style.isEmpty ? "" : "\n")
    }

    static func body(site: CustomCodeBlock?, page: CustomCodeBlock?) -> String {
        let html = [site?.bodyHTML, page?.bodyHTML].compactMap { $0 }
        return html.isEmpty ? "" : html.map { "\n" + $0 }.joined() + "\n"
    }
}

// MARK: - OD-038 per-language output (SF-1007, SF-1506; ADR-0082)

/// OD-038 / SF-1007-003: one language's output tree. The default language is
/// written at the site root; every other language under its route segment.
struct SiteLanguageOutputPass: Sendable {
    /// `nil` for a site without languages.
    let localeID: SiteLocaleID?
    let isDefault: Bool
    /// `""` for the default language, otherwise `/` plus the route segment.
    let routePrefix: String
    /// The `lang` value of `<html>`: the language's code; `en` without languages.
    let language: String
    /// `nil` for a site without languages, which writes no `dir` attribute.
    let direction: SiteTextDirection?
    /// The document as this language shows it; the original for the default.
    let document: CanonicalDocument

    /// `""` at the site root, otherwise e.g. `fr/`.
    var pathPrefix: String { routePrefix.isEmpty ? "" : String(routePrefix.dropFirst()) + "/" }

    var htmlAttributes: String {
        " lang=\"\(language)\"" + (direction.map { " dir=\"\($0.htmlValue)\"" } ?? "")
    }

    /// The page's public address in this language: `/fr/about`, and `/fr/`
    /// for the home page because it is written as `fr/index.html`.
    func route(_ route: PageRoute) -> String {
        guard !routePrefix.isEmpty else { return route.rawValue }
        return route.rawValue == "/" ? routePrefix + "/" : routePrefix + route.rawValue
    }
}

/// OD-038 / SF-1007-002/003/005, SF-1506-003: per-language export. Pure and
/// output-only; it never changes the document.
enum SiteLanguageOutput {
    static let requirementIDs: Set<String> = ["SF-1007-002", "SF-1007-003", "SF-1007-005", "SF-1007-008", "SF-1506-003"]

    /// The default language first (shared styles come from its pages), then
    /// the other languages in the order authors arranged them. A site without
    /// languages has one pass that writes exactly what it always did.
    static func passes(_ document: CanonicalDocument) -> [SiteLanguageOutputPass] {
        guard let localization = document.localization else {
            return [SiteLanguageOutputPass(localeID: nil, isDefault: true, routePrefix: "", language: "en",
                                           direction: nil, document: document)]
        }
        let ordered = localization.locales.filter { $0.id == localization.defaultLocaleID }
            + localization.locales.filter { $0.id != localization.defaultLocaleID }
        return ordered.compactMap { locale -> SiteLanguageOutputPass? in
            guard let resolution = SiteLocaleResolver.resolve(locale.id, in: localization) else { return nil }
            return SiteLanguageOutputPass(localeID: locale.id, isDefault: resolution.isDefault,
                routePrefix: resolution.routePrefix, language: locale.code, direction: resolution.direction,
                document: resolution.isDefault ? document : translatedDocument(document, to: locale.id, in: localization))
        }
    }

    /// The document as one language shows it, for output only (never
    /// committed): every translatable value is replaced by the language's own
    /// translation or a fallback language's; values with neither keep the
    /// default language's. Translation properties are removed.
    static func translatedDocument(_ document: CanonicalDocument, to localeID: SiteLocaleID,
                                   in localization: SiteLocalization) -> CanonicalDocument {
        var copy = document
        for pageIndex in copy.pages.indices {
            for nodeIndex in copy.pages[pageIndex].nodes.indices {
                copy.pages[pageIndex].nodes[nodeIndex] = translatedNode(copy.pages[pageIndex].nodes[nodeIndex],
                                                                        to: localeID, in: localization)
            }
        }
        return copy
    }

    static func translatedNode(_ node: DocumentNode, to localeID: SiteLocaleID,
                               in localization: SiteLocalization) -> DocumentNode {
        var result = node
        for field in SiteTranslationField.fields(for: node.kind) {
            guard let key = field.baseKey(for: node.kind),
                  let resolution = SiteTranslationResolver.resolve(field, on: node, for: localeID, in: localization),
                  resolution.source == .translation || resolution.source == .fallback,
                  let value = resolution.value else { continue }
            if let index = result.properties.firstIndex(where: { $0.key.rawValue == key }) {
                result.properties[index].value = .string(value)
            } else {
                result.properties.append(NodeProperty(key: PropertyKey(rawValue: key), value: .string(value)))
            }
        }
        result.properties.removeAll { $0.key.rawValue.hasPrefix(SiteTranslationKey.namespace) }
        return result
    }

    /// SF-1007-003: links inside a language tree are relative to the page, so
    /// the tree works in its folder without a server that rewrites addresses.
    static func relativeRoutes(_ routes: [PageID: String], from outputPath: String) -> [PageID: String] {
        let directory = outputPath.split(separator: "/").dropLast().map(String.init)
        return routes.mapValues { relativePath(from: directory, to: $0) }
    }

    static func relativePath(from directory: [String], to target: String) -> String {
        let parts = target.split(separator: "/").map(String.init)
        var common = 0
        while common < directory.count, common < parts.count - 1, directory[common] == parts[common] { common += 1 }
        return (Array(repeating: "..", count: directory.count - common) + Array(parts[common...])).joined(separator: "/")
    }

    /// OD-038 (ADR-0087): Website Preview opens a page in the language the
    /// canvas shows, at the path export writes it to (`fr/about.html`). The
    /// default language, `nil` and a language the site no longer has open `path`.
    static func previewPath(_ path: String, showing localeID: SiteLocaleID?, in document: CanonicalDocument) -> String {
        guard let localization = document.localization,
              let id = SiteCanvasLanguage.shownLocale(localeID, in: localization),
              let resolution = SiteLocaleResolver.resolve(id, in: localization),
              !resolution.routePrefix.isEmpty else { return path }
        return String(resolution.routePrefix.dropFirst()) + "/" + path
    }

    /// SF-1007-005: `hreflang` links to every language version of a page and
    /// `x-default` to the default language's. Absolute with the site address;
    /// otherwise the address alone, like the canonical link. Not Found pages
    /// and sites with one language get none.
    static func alternates(route: PageRoute, role: PageRole, passes: [SiteLanguageOutputPass], siteURL: String?) -> String {
        guard passes.count > 1, role != .notFound else { return "" }
        func link(_ hreflang: String, _ address: String) -> String {
            "<link rel=\"alternate\" hreflang=\"\(StaticSEOEmitter.escape(hreflang))\" href=\"\(StaticSEOEmitter.escape((siteURL ?? "") + address))\">"
        }
        var links = passes.map { link($0.language, $0.route(route)) }
        if let main = passes.first(where: \.isDefault) { links.append(link("x-default", main.route(route))) }
        return links.joined()
    }

    /// SF-0807: images that only a translation of a current language shows.
    static func translatedAssetIDs(_ document: CanonicalDocument) -> Set<AssetID> {
        guard let localization = document.localization else { return [] }
        let shown = Set(localization.locales.map(\.id)).subtracting([localization.defaultLocaleID])
        var result = Set<AssetID>()
        for page in document.pages {
            for node in page.nodes {
                for entry in CanonicalTranslations.translations(on: node)
                where entry.key.field == .imageAssetID && shown.contains(entry.key.localeID) {
                    if case .string(let raw) = entry.property.value, let id = AssetID(uuidString: raw) { result.insert(id) }
                }
            }
        }
        return result
    }

    /// SF-1007-002/004/005: translation gaps are visible before export.
    /// Findings carry language addresses and counts only, never text.
    static func findings(document: CanonicalDocument) -> [StaticBuildFinding] {
        guard let localization = document.localization else { return [] }
        let report = SiteTranslationReport.build(document)
        var findings: [StaticBuildFinding] = []
        for locale in localization.locales where locale.id != localization.defaultLocaleID {
            let missing = report.missingCount(locale.id)
            guard missing > 0, let resolution = SiteLocaleResolver.resolve(locale.id, in: localization) else { continue }
            findings.append(.init(severity: .warning, code: "translation-missing", requirementID: "SF-1007-002",
                outputPath: resolution.routePrefix,
                explanation: "\(missing) value(s) are not translated for this language, so its pages show a fallback language's value instead.",
                repair: "Add the missing translations for this language, or keep the fallback text."))
        }
        if report.orphanedCount > 0 {
            findings.append(.init(severity: .information, code: "translation-orphaned", requirementID: "SF-1007-004",
                explanation: "\(report.orphanedCount) translation(s) belong to languages the site no longer has; they are not exported.",
                repair: "Edit the site's languages once to remove them, or add the language again."))
        }
        if localization.locales.count > 1, document.websiteMetadata?.siteURL == nil {
            findings.append(.init(severity: .warning, code: "language-alternates-need-site-url", requirementID: "SF-1007-005",
                explanation: "Language versions link to each other by page address only; search engines need the site's full address to match them.",
                repair: "Enter the site address in Website Settings."))
        }
        return findings
    }
}

enum MultiPageStaticBuildPlanner {
    /// `includesCustomCode` is false for Browser Preview (SF-1107: authored
    /// code never runs inside SiteForge's preview) and true for Check Website
    /// builds.
    static func plan(
        document: CanonicalDocument,
        imageOutputEntries: [StaticAssetExportEntry] = [],
        includesCustomCode: Bool = false,
        fontOutputEntries: [StaticAssetExportEntry] = [],
        mediaOutputEntries: [StaticAssetExportEntry] = []
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
        // OD-045 / SF-0805: @font-face only for faces with declared web rights and verified files.
        let fontPaths = ProjectFontOutput.exportedPaths(fonts: document.fontAssets, entries: fontOutputEntries)
        let fontFallbacks = ProjectFontOutput.fallbackStacks(fonts: document.fontAssets)
        // OD-045 / SF-0803: verified media paths for Images in media mode.
        let mediaPaths = ProjectMediaOutput.exportedPaths(media: document.mediaAssets, entries: mediaOutputEntries)
        let mediaAssets = Dictionary(uniqueKeysWithValues: document.mediaAssets.map { ($0.id, $0) })
        var staticRoutes: [PageID: String] = [:]
        var sectionIDs: [PageID: Set<NodeID>] = [:]
        for page in pages {
            guard staticRoutes[page.id] == nil else { throw MultiPageStaticBuildError.invalidDocument }
            staticRoutes[page.id] = try outputPath(for: page)
            sectionIDs[page.id] = Set(page.canonicalDepthFirstNodes().filter { $0.kind == .section }.map(\.id))
        }
        // SF-1003 (OD-035): each template page is written as one page per
        // published item; links to the template open its first item.
        let outputPages = CollectionTemplates.outputPages(pages, document: document)
        let templatePageIDs = CollectionTemplates.templatePageIDs(document)
        for (pageID, route) in CollectionTemplates.linkTargets(document) {
            staticRoutes[pageID] = try outputPath(for: DocumentPage(id: pageID, name: "Item", route: route))
        }
        // SF-1003-002: links that open one item's page, and Previous/Next
        // links to a list's later pages (identities that are not document pages).
        for (pageID, route) in CollectionLists.linkRoutes(document, pages: pages) {
            staticRoutes[pageID] = try outputPath(for: DocumentPage(id: pageID, name: "Item", route: route))
        }
        var files: [LocalStaticBuildPlan.File] = []
        var paths = Set<String>()
        var staticNodes: [InternalRenderTreeNode] = []
        var staticTrees: [InternalRenderTreeSnapshot] = []
        var darkNodes: [InternalRenderTreeNode] = []
        let hasDarkVariants = document.colorTokens.contains { $0.darkColor != nil }
        let darkTokens = document.colorTokens.map { token in var copy = token; copy.color = token.darkColor ?? token.color; return copy }
        var needsNavigationScript = false
        var needsEffectsRuntime = false
        var needsMotionRuntime = false
        var needsEventRuntime = false, needsHiddenCSS = false, needsOverlayCSS = false
        // V14e: a page with objects always links the stylesheet. Static-layout
        // pages keep their positions, typography and hide rules there too; the
        // file is written whenever a page links it, so the link always resolves.
        var linksStylesheet = false
        // OD-038 / SF-1007 (ADR-0082): one tree per site language. The default
        // language is written at the site root exactly as before; every other
        // language under `<code>/` with its translations applied.
        let languages = SiteLanguageOutput.passes(document)
        var indexableRoutes: [String] = []
        for language in languages {
            let passDocument = language.document
            var passPages = pages
            if !language.isDefault {
                passPages = try passDocument.pages.filter { $0.role != .componentDefinition }.map {
                    try ComponentGraphResolver.resolvedPage($0, in: passDocument, breakpoint: .desktop)
                }
            }
            let passOutputPages = language.isDefault ? outputPages : CollectionTemplates.outputPages(passPages, document: passDocument)
            let passRoutes = language.isDefault ? staticRoutes : staticRoutes.mapValues { language.pathPrefix + $0 }
            indexableRoutes += passOutputPages.map(\.page).filter { page in
                page.role != .notFound && WebsiteMetadataResolver.resolve(page: page, document: passDocument).allowsIndexing
            }.map { language.route($0.route) }
            for entry in passOutputPages.sorted(by: { $0.page.route.rawValue < $1.page.route.rawValue }) {
                // SF-1106 (C6, ADR-0066): a Text bound to a page variable is written with
                // the variable's starting value, after translations and collection items.
                let page = CanonicalTextBinding.outputPage(entry.page)
                let output = try language.pathPrefix + outputPath(for: page)
                // Links are relative to the page, so pages in a folder (a language
                // tree, item pages, a list's later pages) work without a server.
                let pageRoutes = output.contains("/") ? SiteLanguageOutput.relativeRoutes(passRoutes, from: output) : passRoutes
                guard paths.insert(output).inserted else { throw MultiPageStaticBuildError.collision }
                let navigation = StaticNavigationEmitter.emit(
                    StaticNavigationEmitter.entries(
                        pages: document.pages.filter { !templatePageIDs.contains($0.id) },
                        staticRoutes: passRoutes,
                        currentPageID: page.id,
                        currentOutputPath: output
                    )
                )
                let tree = try InternalDocumentRenderTreeCompiler.compile(
                    page: page, documentID: document.id, revision: document.revision,
                    staticRoutes: pageRoutes, sectionIDs: sectionIDs,
                    imageOutputPaths: imageOutputPaths, imageAssets: imageAssets,
                    colorTokens: document.colorTokens,
                    reusableStyleIndex: reusableStyleIndex,
                    mediaAssets: mediaAssets, mediaOutputPaths: mediaPaths
                )
                // Item pages share the template's layers; shared styles come from one of them.
                if entry.isPrimary && language.isDefault {
                    staticNodes += tree.nodes
                    staticTrees.append(tree)
                }
                if hasDarkVariants && entry.isPrimary && language.isDefault {
                    let darkTree = try InternalDocumentRenderTreeCompiler.compile(page: page, documentID: document.id, revision: document.revision,
                        staticRoutes: staticRoutes, sectionIDs: sectionIDs, imageOutputPaths: imageOutputPaths, imageAssets: imageAssets,
                        colorTokens: darkTokens, reusableStyleIndex: reusableStyleIndex)
                    darkNodes += darkTree.nodes
                }
                let effectConfigurations = try DecorativeEffectOutput.configurations(page)
                needsEffectsRuntime = needsEffectsRuntime || !effectConfigurations.isEmpty
                // OD-040: reveal-on-scroll nodes carry their trigger line; any motion links the stylesheet.
                let entrances = try MotionOutput.entrances(page)
                let usesMotion = try MotionOutput.usesMotion(page)
                needsMotionRuntime = needsMotionRuntime || !entrances.isEmpty
                // OD-039: compiled interactions (routes relative to this page) and start-hidden nodes.
                let events = try EventGraphOutput.page(page, staticRoutes: passRoutes,
                    prefix: String(repeating: "../", count: max(0, output.split(separator: "/").count - 1)))
                needsEventRuntime = needsEventRuntime || events.needsRuntime
                needsOverlayCSS = needsOverlayCSS || events.hasOverlays
                // Static layout gives every object an explicit `display`, so anything
                // the runtime hides later needs the hidden rule as well.
                needsHiddenCSS = needsHiddenCSS || !events.startsHidden.isEmpty || events.needsRuntime
                let body = try SafeHTMLEmitter.emit(tree, layoutContainers: ConnectedFluidOutputPolicy.wrapperIDs(page), flowConfigurations: effectConfigurations, entrances: entrances,
                                                    events: events.configurations, startsHidden: events.startsHidden, attributes: events.htmlAttributes,
                                                    queryWrappers: StaticContainerQueryWrapping.openingTags(page))
                // Image sources are written from the site root; in a folder (a language
                // tree, item pages, a list's later pages) they start at the page's
                // folder. Authored text and attributes are escaped, so only generated
                // image sources match.
                let assetFolder = String(repeating: "../", count: max(0, output.split(separator: "/").count - 1)) + "assets/"
                let pageBody = !output.contains("/") ? body : body
                    .replacingOccurrences(of: " src=\"assets/", with: " src=\"" + assetFolder)
                    // SF-0803 / SF-1206-004: a video's poster is a generated image source too.
                    .replacingOccurrences(of: " poster=\"assets/", with: " poster=\"" + assetFolder)
                let hasFlow = page.usesConnectedOutput
                let hasMenu = tree.nodes.contains { $0.navigation?.hamburgerEnabled == true }
                needsNavigationScript = needsNavigationScript || hasMenu
                let prefix = String(repeating: "../", count: max(0, output.split(separator: "/").count - 1))
                let stylesheetLink = !page.nodes.isEmpty || hasFlow || usesMotion || !events.isEmpty || !effectConfigurations.isEmpty || page.nodes.contains(where: { (try? CanonicalGlassSurface.resolve($0)) != nil }) || ProjectFontOutput.usesProjectFont(page, fonts: document.fontAssets) ? "<link rel=\"stylesheet\" href=\"\(prefix)styles.css\">" : ""
                linksStylesheet = linksStylesheet || !stylesheetLink.isEmpty
                var script = (hasMenu ? "<script src=\"\(prefix)siteforge-navigation.js\" defer></script>" : "")
                    + (effectConfigurations.isEmpty ? "" : "<script src=\"\(prefix)siteforge-effects.js\" defer></script>")
                    + (entrances.isEmpty ? "" : "<script src=\"\(prefix)siteforge-motion.js\" defer></script>")
                if events.needsRuntime {
                    // SF-1106: initial variable values travel as escaped data next to the runtime.
                    script += (events.stateJSON.map { "<div hidden data-siteforge-state=\"\(SafeHTMLEmitter.escape($0))\"></div>" } ?? "")
                        + "<script src=\"\(prefix)siteforge-events.js\" defer></script>"
                }
                // SF-1003: an item page's title comes from its item, not from a
                // title set on the template page.
                let metadata = WebsiteMetadataResolver.resolve(page: page, document: passDocument,
                                                               ignoresPageTitle: entry.itemID != nil)
                let socialImagePath = document.websiteMetadata?.socialImageAssetID.flatMap { imageOutputPaths[$0] }
                let seoMetadata = StaticSEOMetadata(siteName: metadata.siteName, title: metadata.title,
                    description: metadata.description, language: language.language,
                    index: metadata.allowsIndexing, follow: true)
                guard let metadataHead = StaticSEOEmitter.head(seoMetadata, route: language.route(page.route),
                    siteURL: document.websiteMetadata?.siteURL, socialImagePath: socialImagePath) else {
                    throw MultiPageStaticBuildError.invalidDocument
                }
                // OD-144 (ADR-0144): structured data from the same typed metadata,
                // only with the site address. Not Found pages get none; a list's
                // later pages are web pages of their own, not the home page.
                let structuredData = page.role == .notFound ? "" : StaticSEOEmitter.structuredData(seoMetadata,
                    route: language.route(page.route), siteRoot: language.routePrefix + "/",
                    isHome: page.role == .home && (entry.listPageNumber ?? 1) == 1,
                    siteURL: document.websiteMetadata?.siteURL)
                let alternates = SiteLanguageOutput.alternates(route: page.route, role: page.role, passes: languages,
                                                               siteURL: document.websiteMetadata?.siteURL)
                let favicon = metadata.faviconAssetID.flatMap { imageOutputPaths[$0] }.map {
                    "<link rel=\"icon\" href=\"\(prefix)\($0)\">"
                } ?? ""
                let siteCode = includesCustomCode ? document.websiteMetadata?.customCode : nil
                let pageCode = includesCustomCode ? document.websiteMetadata?.pages.first(where: { $0.pageID == page.id })?.customCode : nil
                let customHead = CustomCodeOutput.head(site: siteCode, page: pageCode)
                let customBody = CustomCodeOutput.body(site: siteCode, page: pageCode)
                let head = "<head><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\(metadataHead)\(structuredData)\(alternates)\(favicon)\(stylesheetLink)\(customHead)</head>"
                let markup: String
                if hasFlow {
                    // Authored navigation replaces the generated route list; that
                    // historical list must not shift the connected page origin.
                    markup = "<!doctype html><html\(language.htmlAttributes)>\(head)<body class=\"sf-connected-body\" tabindex=\"-1\"><div class=\"sf-connected-page sf-page-\(page.id)\">\(pageBody)</div>\(script)\(customBody)</body></html>"
                } else {
                    let contents = [navigation, pageBody, script].filter { !$0.isEmpty }.joined(separator: "\n")
                    markup = "<!doctype html><html\(language.htmlAttributes)>\(head)<body>\(contents)\(customBody)</body></html>"
                }
                files.append(.init(path: output, contents: markup))
            }
        }
        // The static build plan consumes the same typed responsive cascade as
        // editor layout. This remains an immutable planning artifact: it does
        // not create an authored CSS model or write a generated site.
        // SF-1003-002: a list's copies are styled like their originals; the
        // list's first page holds every copy a later page uses.
        let stylePages = CollectionLists.stylePages(pages, document: document)
        let layout = StaticLayoutOutputEmitter.emit(
            nodes: stylePages.filter { !$0.nodes.contains { CanonicalPageFlow.role($0) != nil } }
                .flatMap { $0.canonicalDepthFirstNodes() },
            // Lane V19: objects a container-query Show rule can reveal are
            // hidden by `StaticVisibilityOutputEmitter` instead.
            revealable: Set(stylePages.flatMap { StaticContainerQueryWrapping.plan($0).shows.keys })
        )
        let typography = StaticTypographyOutputEmitter.emit(nodes: staticNodes, fontFallbacks: fontFallbacks)
        let images = StaticImageStyleOutputEmitter.emit(nodes: staticNodes)
        let fills = StaticFillLayerStyleOutputEmitter.emit(nodes: staticNodes)
        let boxStyles = StaticBoxStyleOutputEmitter.emit(nodes: staticNodes)
        let sizing = StaticSizingOutputEmitter.emit(nodes: staticNodes)
        let advancedStyles = StaticAdvancedStyleOutputEmitter.emit(nodes: staticNodes)
        // ADR-0065: on static-layout pages a container's contents hide and reveal with it.
        let motion = try [MotionOutput.css(stylePages.flatMap(\.nodes)), FlatContainerOutput.css(stylePages)]
            .filter { !$0.isEmpty }.joined(separator: "\n")
        let eventStyles = [needsHiddenCSS ? EventGraphOutput.hiddenCSS : "", needsOverlayCSS ? EventGraphOutput.overlayCSS : ""]
            .filter { !$0.isEmpty }.joined(separator: "\n")
        let fluidTypography = StaticFluidValueOutputEmitter.emit(
            nodes: stylePages.flatMap { $0.canonicalDepthFirstNodes() },
            targets: [.fontSize, .lineHeight])
        // Fluid typography deliberately follows fixed typography. Geometry
        // and spacing fluid rules live inside layout output before explicit
        // breakpoint rules so authored breakpoint literals retain precedence.
        let glass = try DecorativeEffectOutput.glassCSS(stylePages.flatMap(\.nodes))
        // SF-0605: container queries come last so a matching rule wins.
        let containerQueries = StaticContainerQueryOutputEmitter.emit(pages: stylePages, reusableStyles: reusableStyleIndex)
        let stylesheet = [ProjectFontOutput.fontFaceCSS(fonts: document.fontAssets, paths: fontPaths), glass, layout.css, typography, fluidTypography, images, fills, boxStyles, sizing, advancedStyles, motion, eventStyles,
                          ConnectedPageOutput.css(pages: stylePages, colorTokens: document.colorTokens)]
            .filter { !$0.isEmpty }.joined(separator: "\n")
        let darkStyles = hasDarkVariants ? "@media (prefers-color-scheme:dark) {\n" + [
            StaticTypographyOutputEmitter.emit(nodes: darkNodes, fontFallbacks: fontFallbacks), StaticFillLayerStyleOutputEmitter.emit(nodes: darkNodes),
            StaticBoxStyleOutputEmitter.emit(nodes: darkNodes), ConnectedPageOutput.css(pages: stylePages, colorTokens: darkTokens)
        ].filter { !$0.isEmpty }.joined(separator: "\n") + "\n}" : ""
        let darkThemed = stylesheet + (darkStyles.isEmpty ? "" : "\n:root { color-scheme:light dark; }\n" + darkStyles)
        // Lane V14a: hiding rules and container queries follow the dark-mode
        // block, which repeats typography (`…[data-siteforge-node] { display:flex }`,
        // text sizes) at equal specificity, so a hidden object stays hidden and a
        // matching container rule still wins in dark mode.
        let themedStylesheet = [darkThemed, StaticVisibilityOutputEmitter.emit(pages: stylePages), containerQueries]
            .filter { !$0.isEmpty }.joined(separator: "\n")
        let effectStylesheet = needsEffectsRuntime ? themedStylesheet + "\n" + DecorativeEffectRuntime.css : themedStylesheet
        if !effectStylesheet.isEmpty || linksStylesheet {
            guard paths.insert("styles.css").inserted else { throw MultiPageStaticBuildError.collision }
            files.append(.init(path: "styles.css", contents: effectStylesheet))
        }
        if needsEffectsRuntime {
            guard paths.insert("siteforge-effects.js").inserted else { throw MultiPageStaticBuildError.collision }
            files.append(.init(path: "siteforge-effects.js", contents: DecorativeEffectRuntime.javascript))
        }
        if needsNavigationScript {
            guard paths.insert("siteforge-navigation.js").inserted else { throw MultiPageStaticBuildError.collision }
            files.append(.init(path: "siteforge-navigation.js", contents: ConnectedPageOutput.menuScript))
        }
        if needsMotionRuntime {
            guard paths.insert("siteforge-motion.js").inserted else { throw MultiPageStaticBuildError.collision }
            files.append(.init(path: "siteforge-motion.js", contents: MotionRuntime.javascript))
        }
        if needsEventRuntime {
            guard paths.insert("siteforge-events.js").inserted else { throw MultiPageStaticBuildError.collision }
            files.append(.init(path: "siteforge-events.js", contents: EventGraphRuntime.javascript))
        }
        // SF-1207-001: robots.txt always; sitemap.xml once the site address is known.
        let siteIndexing = document.websiteMetadata?.allowsIndexing ?? true
        guard paths.insert("robots.txt").inserted else { throw MultiPageStaticBuildError.collision }
        files.append(.init(path: "robots.txt", contents: StaticSEOEmitter.robots(allowsIndexing: siteIndexing,
                                                                                siteURL: document.websiteMetadata?.siteURL)))
        if let siteURL = document.websiteMetadata?.siteURL {
            // OD-038: every language's indexable pages, collected per language above.
            guard paths.insert("sitemap.xml").inserted else { throw MultiPageStaticBuildError.collision }
            files.append(.init(path: "sitemap.xml", contents: StaticSEOEmitter.sitemap(siteURL: siteURL, routes: indexableRoutes)))
        }
        // The manifest is a plan-side integrity projection only. It names
        // verified content-addressed references but never carries resource
        // bytes or invokes the static writer.
        // SF-1206-001 (ADR-0124): every exported asset type, not only images.
        let assetManifest = StaticAssetManifestEmitter.emit(
            assets: document.imageAssets,
            entries: imageOutputEntries,
            fonts: document.fontAssets, fontPaths: fontPaths,
            media: document.mediaAssets, mediaPaths: mediaPaths
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
    static func escape(_ value: String) -> String {
        SafeHTMLEmitter.escape(value)
    }

    /// SF-1207-001/003: search and social metadata for one page. With a site
    /// address, the canonical and Open Graph URLs are absolute; without one
    /// the canonical link stays the page route and URL-only tags are omitted.
    static func head(_ metadata: StaticSEOMetadata, route: String, siteURL: String? = nil, socialImagePath: String? = nil) -> String? {
        guard !metadata.siteName.isEmpty, !metadata.title.isEmpty, route.first == "/", !route.contains("?") && !route.contains("#") else { return nil }
        let description = metadata.description.map { "<meta name=\"description\" content=\"\(escape($0))\">" } ?? ""
        let absolute = siteURL.map { $0 + route }
        var head = "<meta charset=\"utf-8\"><title>\(escape(metadata.title))</title>\(description)<meta name=\"robots\" content=\"\(metadata.index ? "index" : "noindex"), \(metadata.follow ? "follow" : "nofollow")\"><link rel=\"canonical\" href=\"\(escape(absolute ?? route))\">"
        var social = [
            "<meta property=\"og:type\" content=\"website\">",
            "<meta property=\"og:site_name\" content=\"\(escape(metadata.siteName))\">",
            "<meta property=\"og:title\" content=\"\(escape(metadata.title))\">",
        ]
        if let text = metadata.description { social.append("<meta property=\"og:description\" content=\"\(escape(text))\">") }
        if let absolute { social.append("<meta property=\"og:url\" content=\"\(escape(absolute))\">") }
        // Open Graph requires an absolute image URL.
        if let siteURL, let socialImagePath {
            social.append("<meta property=\"og:image\" content=\"\(escape(siteURL + "/" + socialImagePath))\">")
            social.append("<meta name=\"twitter:card\" content=\"summary_large_image\">")
        } else {
            social.append("<meta name=\"twitter:card\" content=\"summary\">")
        }
        head += social.joined()
        return head
    }

    /// OD-144 (ADR-0144): schema.org structured data for one written page, as
    /// one `<script type="application/ld+json">`, generated only from typed
    /// metadata (site name, page title, description, language and absolute
    /// address; never authored JSON) and only when the site address is set.
    /// Every page is a `WebPage` that is part of its language tree's
    /// `WebSite`; the home page of each tree also describes that `WebSite`.
    /// Keys are written in one fixed order, so the same project always gives
    /// the same bytes. `siteRoot` is the tree's root route (`/` or `/fr/`).
    static func structuredData(_ metadata: StaticSEOMetadata, route: String, siteRoot: String, isHome: Bool,
                               siteURL: String?) -> String {
        guard let siteURL, !metadata.siteName.isEmpty, !metadata.title.isEmpty,
              route.first == "/", siteRoot.first == "/" else { return "" }
        func string(_ value: String) -> String { "\"" + jsonEscape(value) + "\"" }
        let address = siteURL + route
        let websiteID = siteURL + siteRoot + "#website"
        var page = "{\"@type\":\"WebPage\",\"@id\":\(string(address + "#webpage")),\"url\":\(string(address)),\"name\":\(string(metadata.title))"
        if let description = metadata.description { page += ",\"description\":\(string(description))" }
        page += ",\"inLanguage\":\(string(metadata.language)),\"isPartOf\":{\"@id\":\(string(websiteID))}}"
        var graph = [page]
        if isHome {
            graph.insert("{\"@type\":\"WebSite\",\"@id\":\(string(websiteID)),\"url\":\(string(siteURL + siteRoot)),\"name\":\(string(metadata.siteName)),\"inLanguage\":\(string(metadata.language))}", at: 0)
        }
        return "<script type=\"application/ld+json\">{\"@context\":\"https://schema.org\",\"@graph\":[\(graph.joined(separator: ","))]}</script>"
    }

    /// JSON string contents that are also safe inside an HTML `<script>`
    /// element: `<`, `>` and `&` are `\u` escapes, so authored text can never
    /// close the element (`</script`) or open a comment, and the line and
    /// paragraph separators are escaped too.
    static func jsonEscape(_ value: String) -> String {
        var output = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case "<", ">", "&", "\u{2028}", "\u{2029}": output += String(format: "\\u%04x", scalar.value)
            default:
                if scalar.value < 0x20 { output += String(format: "\\u%04x", scalar.value) } else { output.unicodeScalars.append(scalar) }
            }
        }
        return output
    }

    /// SF-1207-001: `sitemap.xml` listing every indexable website page, when
    /// a site address is set. Not Found pages and pages that discourage
    /// indexing are left out.
    static func sitemap(siteURL: String, routes: [String]) -> String {
        let entries = routes.sorted().map { "<url><loc>\(escape(siteURL + $0))</loc></url>" }.joined(separator: "\n")
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
            + entries + (entries.isEmpty ? "" : "\n") + "</urlset>\n"
    }

    /// SF-1207-001: `robots.txt` following the website's indexing preference.
    static func robots(allowsIndexing: Bool, siteURL: String?) -> String {
        var lines = ["User-agent: *", allowsIndexing ? "Allow: /" : "Disallow: /"]
        if allowsIndexing, let siteURL { lines.append("Sitemap: \(siteURL)/sitemap.xml") }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// SF-1207-004/008: search and sharing problems found before export, as
/// warnings with the page they affect. Lengths follow common search-result
/// truncation (about 60 characters for titles, 160 for descriptions).
enum StaticSEOAudit {
    static let maximumTitleCharacters = 60
    static let maximumDescriptionCharacters = 160

    static func findings(document: CanonicalDocument) -> [StaticBuildFinding] {
        var findings: [StaticBuildFinding] = []
        var titles: [String: [DocumentPage]] = [:]
        // The pages a build writes, resolved as export resolves them: each
        // published item page takes its title from its item (dynamic routes,
        // SF-1003), the template page itself is never written, and a list's
        // later pages repeat its first page's metadata, so only that is checked.
        for entry in CollectionTemplates.outputPages(document.websitePages, document: document)
        where entry.page.role != .notFound && (entry.listPageNumber ?? 1) == 1 {
            let page = entry.page
            let metadata = WebsiteMetadataResolver.resolve(page: page, document: document, ignoresPageTitle: entry.itemID != nil)
            guard metadata.allowsIndexing else { continue }
            titles[metadata.title.lowercased(), default: []].append(page)
            if metadata.description == nil {
                findings.append(.init(severity: .warning, code: "seo-description-missing", requirementID: "SF-1207-004",
                    outputPath: page.route.rawValue, explanation: "This page has no description, so search results show text chosen by the search engine.",
                    repair: "Add a description for this page or a default description in Website Settings."))
            } else if let description = metadata.description, description.count > maximumDescriptionCharacters {
                findings.append(.init(severity: .warning, code: "seo-description-long", requirementID: "SF-1207-004",
                    outputPath: page.route.rawValue, explanation: "This page's description has \(description.count) characters; search results usually show about \(maximumDescriptionCharacters).",
                    repair: "Shorten the description in Website Settings."))
            }
            if metadata.title.count > maximumTitleCharacters {
                findings.append(.init(severity: .warning, code: "seo-title-long", requirementID: "SF-1207-004",
                    outputPath: page.route.rawValue, explanation: "This page's title has \(metadata.title.count) characters; search results usually show about \(maximumTitleCharacters).",
                    repair: "Shorten the page title or the title pattern in Website Settings."))
            }
        }
        for (_, pages) in titles where pages.count > 1 {
            for page in pages.sorted(by: { $0.route.rawValue < $1.route.rawValue }) {
                findings.append(.init(severity: .warning, code: "seo-title-duplicate", requirementID: "SF-1207-004",
                    outputPath: page.route.rawValue, explanation: "\(pages.count) pages share this title, so search results can't tell them apart.",
                    repair: "Give each page its own title in Website Settings."))
            }
        }
        if let metadata = document.websiteMetadata, metadata.socialImageAssetID != nil, metadata.siteURL == nil {
            findings.append(.init(severity: .warning, code: "seo-social-image-needs-site-url", requirementID: "SF-1207-004",
                explanation: "Shared links can't show the social image without the site's address.",
                repair: "Enter the site address in Website Settings."))
        }
        return findings
    }
}

// MARK: - SF-1204 CSS generation and optimization (OD-042, ADR-0120)

/// SF-1204-003/008: what a build did to one generated stylesheet. Sizes and
/// counts only; it never carries selectors, values or authored text.
struct StaticCSSOptimizationReport: Equatable, Sendable {
    let path: String
    let originalBytes: Int
    let outputBytes: Int
    /// False for Development (written exactly as generated) and when
    /// optimization was skipped.
    let isOptimized: Bool
    var removedDuplicateDeclarations = 0
    var removedDuplicateRules = 0
    var removedUnusedRules = 0
    var removedEmptyRules = 0
    /// Set when the stylesheet could not be optimized safely and was written unchanged.
    var skippedReason: String? = nil

    static func readable(path: String, css: String) -> StaticCSSOptimizationReport {
        StaticCSSOptimizationReport(path: path, originalBytes: css.utf8.count, outputBytes: css.utf8.count, isOptimized: false)
    }

    var savedBytes: Int { max(0, originalBytes - outputBytes) }

    var summary: String {
        // Binary units (1 KB = 1,024 bytes), like the Output files report and the budgets.
        let original = ByteCountFormatter.string(fromByteCount: Int64(originalBytes), countStyle: .binary)
        if let skippedReason {
            return "\(path): \(original), written unminified because it could not be optimized safely (\(skippedReason))."
        }
        guard isOptimized else { return "\(path): \(original), readable (Development profile)." }
        let output = ByteCountFormatter.string(fromByteCount: Int64(outputBytes), countStyle: .binary)
        let percent = originalBytes == 0 ? 0 : savedBytes * 100 / originalBytes
        var removed: [String] = []
        if removedDuplicateRules > 0 { removed.append("\(removedDuplicateRules) duplicate rule(s)") }
        if removedDuplicateDeclarations > 0 { removed.append("\(removedDuplicateDeclarations) repeated declaration(s)") }
        if removedUnusedRules > 0 { removed.append("\(removedUnusedRules) rule(s) for objects no page contains") }
        if removedEmptyRules > 0 { removed.append("\(removedEmptyRules) empty rule(s)") }
        let detail = removed.isEmpty ? "." : "; removed " + removed.joined(separator: ", ") + "."
        return "\(path): \(original) → \(output), \(percent)% smaller" + detail
    }
}

/// SF-1204-003: one generated rule that targets an object, in cascade order.
/// A later entry with the same conditions and selector wins over an earlier one.
struct StaticCSSTraceEntry: Equatable, Sendable {
    /// Enclosing at-rule conditions, outermost first; empty when the rule always applies.
    let conditions: [String]
    let selector: String
    let declarations: [String]
}

/// SF-1204 (ADR-0120): Static Release stylesheet optimizer for SiteForge's own
/// generated CSS. It never reorders statements, so the cascade is unchanged.
/// It minifies whitespace, drops comments, and removes only what cannot
/// change the result: an earlier exact copy of a later declaration in the same
/// block, an earlier exact copy of a later sibling statement, empty rules and
/// empty condition blocks, and rules whose every selector names an object that
/// no page or script contains. Anything it does not fully understand (unknown
/// at-rules, nested rules, unbalanced text) leaves the stylesheet unchanged.
enum StaticCSSOptimizer {
    enum CSSFailure: String, Error, Equatable, Sendable {
        case unbalanced = "unbalanced braces, brackets or quotes"
        case unsupportedAtRule = "unsupported at-rule"
        case nestedRule = "nested rule"
        case malformed = "malformed selector or declaration"
    }

    struct Output: Equatable, Sendable {
        let css: String
        let report: StaticCSSOptimizationReport
    }

    /// `usedIdentifiers` nil keeps every rule; otherwise a rule is removed when
    /// every selector in it names an object identifier missing from the set.
    static func optimize(_ css: String, path: String = "styles.css", usedIdentifiers: Set<String>? = nil) -> Output {
        var counts = CSSCounts()
        do {
            var parser = CSSParser(bytes: Array(css.utf8))
            let statements = try parser.parseList(closing: false, context: .topLevel)
            let cleaned = clean(statements, context: .topLevel, used: usedIdentifiers, counts: &counts)
            let output = cleaned.map(\.serialized).joined()
            let report = StaticCSSOptimizationReport(path: path, originalBytes: css.utf8.count,
                outputBytes: output.utf8.count, isOptimized: true,
                removedDuplicateDeclarations: counts.duplicateDeclarations, removedDuplicateRules: counts.duplicateRules,
                removedUnusedRules: counts.unusedRules, removedEmptyRules: counts.emptyRules)
            return Output(css: output, report: report)
        } catch {
            let reason = (error as? CSSFailure)?.rawValue ?? CSSFailure.malformed.rawValue
            let report = StaticCSSOptimizationReport(path: path, originalBytes: css.utf8.count,
                outputBytes: css.utf8.count, isOptimized: false, skippedReason: reason)
            return Output(css: css, report: report)
        }
    }

    /// Minified text with every rule kept; the input itself when it cannot be optimized.
    static func minify(_ css: String) -> String {
        optimize(css).css
    }

    /// Object identifiers (UUID text, exact case, as CSS matches them) that
    /// appear anywhere in the given page and script texts.
    static func usedIdentifiers(in texts: [String]) -> Set<String> {
        var result = Set<String>()
        for text in texts { result.formUnion(identifiers(in: Array(text.utf8))) }
        return result
    }

    /// SF-1204-003: the generated rules that name one object, in source order,
    /// with their conditions. Empty when the stylesheet cannot be read.
    static func trace(_ css: String, nodeID: NodeID) -> [StaticCSSTraceEntry] {
        var parser = CSSParser(bytes: Array(css.utf8))
        guard let statements = try? parser.parseList(closing: false, context: .topLevel) else { return [] }
        let identifier = nodeID.rawValue.uuidString.lowercased()
        var entries: [StaticCSSTraceEntry] = []
        func visit(_ list: [CSSStatement], conditions: [String]) {
            for statement in list {
                switch statement.kind {
                case .rule:
                    if statement.head.contains(identifier) {
                        entries.append(StaticCSSTraceEntry(conditions: conditions, selector: statement.head,
                                                           declarations: statement.declarations))
                    }
                case .group, .layer, .keyframes:
                    visit(statement.children, conditions: conditions + [statement.head])
                case .declarationAtRule, .statement:
                    break
                }
            }
        }
        visit(statements, conditions: [])
        return entries
    }

    // MARK: Parsing

    fileprivate enum CSSByte {
        static let space = UInt8(ascii: " ")
        static let tab = UInt8(ascii: "\t")
        static let newline = UInt8(ascii: "\n")
        static let carriageReturn = UInt8(ascii: "\r")
        static let formFeed: UInt8 = 0x0C
        static let quote = UInt8(ascii: "\"")
        static let apostrophe = UInt8(ascii: "'")
        static let backslash = UInt8(ascii: "\\")
        static let slash = UInt8(ascii: "/")
        static let star = UInt8(ascii: "*")
        static let openParen = UInt8(ascii: "(")
        static let closeParen = UInt8(ascii: ")")
        static let openBracket = UInt8(ascii: "[")
        static let closeBracket = UInt8(ascii: "]")
        static let openBrace = UInt8(ascii: "{")
        static let closeBrace = UInt8(ascii: "}")
        static let semicolon = UInt8(ascii: ";")
        static let colon = UInt8(ascii: ":")
        static let comma = UInt8(ascii: ",")
        static let at = UInt8(ascii: "@")
        static let dash = UInt8(ascii: "-")
        static let underscore = UInt8(ascii: "_")
        static let greater = UInt8(ascii: ">")
        static let plus = UInt8(ascii: "+")
        static let tilde = UInt8(ascii: "~")
    }

    fileprivate enum CSSContext: Equatable { case topLevel, group, keyframes }

    fileprivate struct CSSStatement: Equatable {
        enum Kind: Equatable { case rule, group, layer, keyframes, declarationAtRule, statement }
        var kind: Kind
        /// Minified selector, or `@name prelude` for at-rules.
        var head: String
        var declarations: [String] = []
        var children: [CSSStatement] = []

        var serialized: String {
            switch kind {
            case .statement:
                return head + ";"
            case .rule, .declarationAtRule:
                return head + "{" + declarations.joined(separator: ";") + "}"
            case .group, .layer, .keyframes:
                return head + "{" + children.map(\.serialized).joined() + "}"
            }
        }

        /// `@layer` order and block-less at-rules depend on their first position.
        var isDeduplicable: Bool { kind != .statement && kind != .layer }
    }

    fileprivate struct CSSCounts {
        var duplicateDeclarations = 0
        var duplicateRules = 0
        var unusedRules = 0
        var emptyRules = 0
    }

    fileprivate static let groupAtRules: Set<String> = ["media", "supports", "container", "document", "scope", "starting-style"]
    fileprivate static let keyframesAtRules: Set<String> = ["keyframes", "-webkit-keyframes", "-moz-keyframes"]
    fileprivate static let declarationAtRules: Set<String> = ["font-face", "page", "property", "counter-style",
                                                              "font-palette-values", "view-transition"]
    fileprivate static let statementAtRules: Set<String> = ["import", "charset", "namespace", "layer"]

    fileprivate struct CSSParser {
        let bytes: [UInt8]
        var index = 0

        mutating func skipTrivia() throws {
            while index < bytes.count {
                if StaticCSSOptimizer.isWhitespace(bytes[index]) {
                    index += 1
                } else if bytes[index] == CSSByte.slash, index + 1 < bytes.count, bytes[index + 1] == CSSByte.star {
                    guard let end = StaticCSSOptimizer.commentEnd(bytes, from: index + 2) else { throw CSSFailure.unbalanced }
                    index = end
                } else {
                    break
                }
            }
        }

        /// Reads to the first byte of `stops` outside quotes, comments, brackets
        /// and parentheses; comments become one space. Nil at the end of input.
        mutating func read(until stops: [UInt8]) throws -> (text: [UInt8], stop: UInt8)? {
            var text: [UInt8] = []
            var depth = 0
            while index < bytes.count {
                let byte = bytes[index]
                if byte == CSSByte.quote || byte == CSSByte.apostrophe {
                    text.append(byte)
                    index += 1
                    while true {
                        guard index < bytes.count else { throw CSSFailure.unbalanced }
                        let inner = bytes[index]
                        text.append(inner)
                        index += 1
                        if inner == CSSByte.backslash {
                            guard index < bytes.count else { throw CSSFailure.unbalanced }
                            text.append(bytes[index])
                            index += 1
                        } else if inner == byte {
                            break
                        } else if inner == CSSByte.newline {
                            throw CSSFailure.unbalanced
                        }
                    }
                    continue
                }
                if byte == CSSByte.backslash {
                    guard index + 1 < bytes.count else { throw CSSFailure.unbalanced }
                    text.append(byte)
                    text.append(bytes[index + 1])
                    index += 2
                    continue
                }
                if byte == CSSByte.slash, index + 1 < bytes.count, bytes[index + 1] == CSSByte.star {
                    guard let end = StaticCSSOptimizer.commentEnd(bytes, from: index + 2) else { throw CSSFailure.unbalanced }
                    index = end
                    text.append(CSSByte.space)
                    continue
                }
                if byte == CSSByte.openParen || byte == CSSByte.openBracket {
                    depth += 1
                } else if byte == CSSByte.closeParen || byte == CSSByte.closeBracket {
                    depth -= 1
                    guard depth >= 0 else { throw CSSFailure.unbalanced }
                } else if depth == 0 {
                    if stops.contains(byte) { return (text: text, stop: byte) }
                    if byte == CSSByte.closeBrace { throw CSSFailure.unbalanced }
                    if byte == CSSByte.openBrace { throw CSSFailure.nestedRule }
                }
                text.append(byte)
                index += 1
            }
            return nil
        }

        mutating func parseList(closing: Bool, context: CSSContext) throws -> [CSSStatement] {
            var list: [CSSStatement] = []
            while true {
                try skipTrivia()
                guard index < bytes.count else {
                    if closing { throw CSSFailure.unbalanced }
                    return list
                }
                let byte = bytes[index]
                if byte == CSSByte.closeBrace {
                    guard closing else { throw CSSFailure.unbalanced }
                    index += 1
                    return list
                }
                if byte == CSSByte.at {
                    guard context != .keyframes else { throw CSSFailure.unsupportedAtRule }
                    index += 1
                    let nameStart = index
                    while index < bytes.count, StaticCSSOptimizer.isNameByte(bytes[index]) { index += 1 }
                    guard index > nameStart else { throw CSSFailure.unsupportedAtRule }
                    let name = String(decoding: bytes[nameStart..<index], as: UTF8.self)
                    let lowered = name.lowercased()
                    guard let found = try read(until: [CSSByte.openBrace, CSSByte.semicolon]) else { throw CSSFailure.unbalanced }
                    index += 1
                    let prelude = StaticCSSOptimizer.minifyPrelude(found.text)
                    let head = "@" + name + (prelude.isEmpty ? "" : " " + prelude)
                    if found.stop == CSSByte.semicolon {
                        guard StaticCSSOptimizer.statementAtRules.contains(lowered) else { throw CSSFailure.unsupportedAtRule }
                        list.append(CSSStatement(kind: .statement, head: head))
                    } else if StaticCSSOptimizer.groupAtRules.contains(lowered) || lowered == "layer" {
                        let children = try parseList(closing: true, context: .group)
                        list.append(CSSStatement(kind: lowered == "layer" ? .layer : .group, head: head, children: children))
                    } else if StaticCSSOptimizer.keyframesAtRules.contains(lowered) {
                        let children = try parseList(closing: true, context: .keyframes)
                        list.append(CSSStatement(kind: .keyframes, head: head, children: children))
                    } else if StaticCSSOptimizer.declarationAtRules.contains(lowered) {
                        let declarations = try parseDeclarations()
                        list.append(CSSStatement(kind: .declarationAtRule, head: head, declarations: declarations))
                    } else {
                        throw CSSFailure.unsupportedAtRule
                    }
                } else {
                    guard let found = try read(until: [CSSByte.openBrace]) else { throw CSSFailure.unbalanced }
                    index += 1
                    let selector = StaticCSSOptimizer.minifySelector(found.text)
                    guard !selector.isEmpty else { throw CSSFailure.malformed }
                    let declarations = try parseDeclarations()
                    list.append(CSSStatement(kind: .rule, head: selector, declarations: declarations))
                }
            }
        }

        mutating func parseDeclarations() throws -> [String] {
            guard let found = try read(until: [CSSByte.closeBrace]) else { throw CSSFailure.unbalanced }
            index += 1
            var declarations: [String] = []
            for piece in StaticCSSOptimizer.split(found.text, at: CSSByte.semicolon) {
                let trimmed = StaticCSSOptimizer.trim(piece)
                guard !trimmed.isEmpty else { continue }
                guard let colon = StaticCSSOptimizer.firstIndex(of: CSSByte.colon, in: trimmed) else { throw CSSFailure.malformed }
                let name = StaticCSSOptimizer.trim(Array(trimmed[..<colon]))
                guard !name.isEmpty, !name.contains(where: { StaticCSSOptimizer.isWhitespace($0) }) else { throw CSSFailure.malformed }
                let rawValue = Array(trimmed[(colon + 1)...])
                // Custom property values are kept exactly (trimmed): scripts may read them.
                let isCustomProperty = name.count > 2 && name[0] == CSSByte.dash && name[1] == CSSByte.dash
                let value = isCustomProperty ? StaticCSSOptimizer.trim(rawValue) : StaticCSSOptimizer.minifyValue(rawValue)
                guard isCustomProperty || !value.isEmpty else { throw CSSFailure.malformed }
                declarations.append(String(decoding: name + [CSSByte.colon] + value, as: UTF8.self))
            }
            return declarations
        }
    }

    // MARK: Cleaning

    private static func clean(_ list: [CSSStatement], context: CSSContext, used: Set<String>?,
                              counts: inout CSSCounts) -> [CSSStatement] {
        var kept: [CSSStatement] = []
        for original in list {
            var statement = original
            switch statement.kind {
            case .rule:
                statement.declarations = deduplicated(statement.declarations, counts: &counts)
                if context != .keyframes {
                    if statement.declarations.isEmpty {
                        counts.emptyRules += 1
                        continue
                    }
                    if let used, isUnused(selector: statement.head, used: used) {
                        counts.unusedRules += 1
                        continue
                    }
                }
            case .group:
                statement.children = clean(statement.children, context: .group, used: used, counts: &counts)
                if statement.children.isEmpty {
                    counts.emptyRules += 1
                    continue
                }
            case .layer:
                statement.children = clean(statement.children, context: .group, used: used, counts: &counts)
            case .keyframes:
                statement.children = clean(statement.children, context: .keyframes, used: used, counts: &counts)
            case .declarationAtRule:
                statement.declarations = deduplicated(statement.declarations, counts: &counts)
            case .statement:
                break
            }
            kept.append(statement)
        }
        // A later exact copy of a sibling statement dominates the earlier one:
        // same conditions, same selectors, same declarations, later position.
        var seen = Set<String>()
        var result: [CSSStatement] = []
        for statement in kept.reversed() {
            if statement.isDeduplicable, !seen.insert(statement.serialized).inserted {
                counts.duplicateRules += 1
                continue
            }
            result.append(statement)
        }
        return Array(result.reversed())
    }

    private static func deduplicated(_ declarations: [String], counts: inout CSSCounts) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for declaration in declarations.reversed() {
            guard seen.insert(declaration).inserted else {
                counts.duplicateDeclarations += 1
                continue
            }
            result.append(declaration)
        }
        return Array(result.reversed())
    }

    /// True only when every comma-separated selector names at least one object
    /// identifier that no page contains, and has no functional pseudo-class
    /// (`:not(…)` would match more, not less) or substring attribute operator.
    fileprivate static func isUnused(selector: String, used: Set<String>) -> Bool {
        let unsafeOperators = ["(", "*=", "^=", "$=", "|=", "~="]
        for part in split(Array(selector.utf8), at: CSSByte.comma) {
            let text = String(decoding: part, as: UTF8.self)
            guard !unsafeOperators.contains(where: { text.contains($0) }) else { return false }
            let ids = identifiers(in: part)
            guard !ids.isEmpty, !ids.isSubset(of: used) else { return false }
        }
        return true
    }

    // MARK: Byte helpers

    fileprivate static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == CSSByte.space || byte == CSSByte.tab || byte == CSSByte.newline
            || byte == CSSByte.carriageReturn || byte == CSSByte.formFeed
    }

    fileprivate static func isNameByte(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
            || byte == CSSByte.dash || byte == CSSByte.underscore
    }

    fileprivate static func isHex(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x46) || (byte >= 0x61 && byte <= 0x66)
    }

    fileprivate static func commentEnd(_ bytes: [UInt8], from start: Int) -> Int? {
        var cursor = start
        while cursor + 1 < bytes.count {
            if bytes[cursor] == CSSByte.star && bytes[cursor + 1] == CSSByte.slash { return cursor + 2 }
            cursor += 1
        }
        return nil
    }

    fileprivate static func trim(_ bytes: [UInt8]) -> [UInt8] {
        guard let first = bytes.firstIndex(where: { !isWhitespace($0) }),
              let last = bytes.lastIndex(where: { !isWhitespace($0) }) else { return [] }
        return Array(bytes[first...last])
    }

    /// Visits each byte with whether it is quoted or escaped and its bracket
    /// and parenthesis depth (an opening byte reports the outer depth, a
    /// closing byte the depth after it closes).
    fileprivate static func scan(_ bytes: [UInt8], _ visit: (_ index: Int, _ byte: UInt8, _ quoted: Bool, _ depth: Int) -> Void) {
        var cursor = 0
        var depth = 0
        while cursor < bytes.count {
            let byte = bytes[cursor]
            if byte == CSSByte.quote || byte == CSSByte.apostrophe {
                var end = cursor + 1
                while end < bytes.count, bytes[end] != byte {
                    if bytes[end] == CSSByte.backslash { end += 1 }
                    end += 1
                }
                for position in cursor..<min(end + 1, bytes.count) { visit(position, bytes[position], true, depth) }
                cursor = end + 1
                continue
            }
            if byte == CSSByte.backslash {
                visit(cursor, byte, true, depth)
                if cursor + 1 < bytes.count { visit(cursor + 1, bytes[cursor + 1], true, depth) }
                cursor += 2
                continue
            }
            if byte == CSSByte.openParen || byte == CSSByte.openBracket {
                visit(cursor, byte, false, depth)
                depth += 1
            } else if byte == CSSByte.closeParen || byte == CSSByte.closeBracket {
                depth -= 1
                visit(cursor, byte, false, depth)
            } else {
                visit(cursor, byte, false, depth)
            }
            cursor += 1
        }
    }

    fileprivate static func split(_ bytes: [UInt8], at separator: UInt8) -> [[UInt8]] {
        var parts: [[UInt8]] = []
        var start = 0
        scan(bytes) { index, byte, quoted, depth in
            if !quoted, depth == 0, byte == separator {
                parts.append(Array(bytes[start..<index]))
                start = index + 1
            }
        }
        parts.append(Array(bytes[start...]))
        return parts
    }

    fileprivate static func firstIndex(of target: UInt8, in bytes: [UInt8]) -> Int? {
        var found: Int?
        scan(bytes) { index, byte, quoted, depth in
            if found == nil, !quoted, depth == 0, byte == target { found = index }
        }
        return found
    }

    /// Declaration values: whitespace runs become one space; no space after
    /// `(` or `,`, or before `)` or `,`. Quoted text is kept exactly.
    fileprivate static func minifyValue(_ bytes: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        var pendingSpace = false
        scan(bytes) { _, byte, quoted, _ in
            if !quoted, isWhitespace(byte) {
                pendingSpace = true
                return
            }
            if pendingSpace, let last = output.last, last != CSSByte.openParen, last != CSSByte.comma,
               quoted || (byte != CSSByte.closeParen && byte != CSSByte.comma) {
                output.append(CSSByte.space)
            }
            pendingSpace = false
            output.append(byte)
        }
        return output
    }

    /// At-rule preludes: whitespace runs become one space; nothing else changes.
    fileprivate static func minifyPrelude(_ bytes: [UInt8]) -> String {
        var output: [UInt8] = []
        var pendingSpace = false
        scan(bytes) { _, byte, quoted, _ in
            if !quoted, isWhitespace(byte) {
                pendingSpace = true
                return
            }
            if pendingSpace, !output.isEmpty { output.append(CSSByte.space) }
            pendingSpace = false
            output.append(byte)
        }
        return String(decoding: output, as: UTF8.self)
    }

    /// Selectors: whitespace runs become one space (a descendant combinator);
    /// spaces around `,`, `>`, `+` and `~` outside brackets and parentheses go.
    fileprivate static func minifySelector(_ bytes: [UInt8]) -> String {
        var output: [UInt8] = []
        var pendingSpace = false
        var afterCombinator = false
        scan(bytes) { _, byte, quoted, depth in
            if !quoted, isWhitespace(byte) {
                pendingSpace = true
                return
            }
            if !quoted, depth == 0,
               byte == CSSByte.comma || byte == CSSByte.greater || byte == CSSByte.plus || byte == CSSByte.tilde {
                pendingSpace = false
                afterCombinator = true
                output.append(byte)
                return
            }
            if pendingSpace, !afterCombinator, !output.isEmpty { output.append(CSSByte.space) }
            pendingSpace = false
            afterCombinator = false
            output.append(byte)
        }
        return String(decoding: output, as: UTF8.self)
    }

    /// UUID-shaped identifiers (8-4-4-4-12 hexadecimal digits, not part of a
    /// longer hexadecimal run), exactly as written.
    fileprivate static func identifiers(in bytes: [UInt8]) -> Set<String> {
        var result = Set<String>()
        let groups = [8, 4, 4, 4, 12]
        var index = 0
        while index + 36 <= bytes.count {
            guard isHex(bytes[index]), index == 0 || !isHex(bytes[index - 1]) else {
                index += 1
                continue
            }
            var cursor = index
            var matches = true
            for (offset, length) in groups.enumerated() {
                if offset > 0 {
                    if bytes[cursor] == CSSByte.dash { cursor += 1 } else { matches = false; break }
                }
                for _ in 0..<length {
                    if isHex(bytes[cursor]) { cursor += 1 } else { matches = false; break }
                }
                if !matches { break }
            }
            if matches, cursor == bytes.count || !isHex(bytes[cursor]) {
                result.insert(String(decoding: bytes[index..<cursor], as: UTF8.self))
                index = cursor
            } else {
                index += 1
            }
        }
        return result
    }
}

// MARK: - SF-1206 static asset export: integrity manifest and references (OD-042, ADR-0121)

/// SF-1206-001/003: how long a browser or host may keep one output file.
enum StaticOutputCachePolicy: String, Codable, Equatable, Sendable {
    /// Content-addressed (`assets/<sha256>.<ext>`, and Static Release's runtime
    /// `siteforge-runtime.<sha256>.js`, ADR-0124): the name changes whenever the bytes do.
    case immutable
    /// Pages, stylesheets, Development's readable scripts and site files keep their names; check for a newer copy.
    case revalidate

    static func policy(for path: String) -> StaticOutputCachePolicy {
        path.range(of: "^assets/[a-f0-9]{64}\\.[a-z0-9]+$", options: .regularExpression) != nil
            || StaticRuntimeBundle.isBundlePath(path) ? .immutable : .revalidate
    }
}

/// SF-1206-001/008: one written file in the build's integrity manifest.
struct StaticOutputFileRecord: Codable, Equatable, Sendable {
    let path: String
    let bytes: Int
    let sha256: String
    let cache: StaticOutputCachePolicy
}

/// SF-1206 (ADR-0121): every file a build writes with its size, SHA-256 and
/// cache policy, sorted by path. Static Release also writes it as
/// `siteforge-integrity.json` (which does not list itself). It carries no
/// revision or time, so the same output always produces the same manifest.
struct StaticOutputManifest: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let fileName = "siteforge-integrity.json"
    let version: Int
    let files: [StaticOutputFileRecord]

    init(files textFiles: [LocalStaticBuildPlan.File], binaryFiles: [LocalStaticBuildPlan.BinaryFile]) {
        let text = textFiles.filter { $0.path != StaticOutputManifest.fileName }.map { file -> StaticOutputFileRecord in
            let data = Data(file.contents.utf8)
            return StaticOutputFileRecord(path: file.path, bytes: data.count, sha256: ProjectResourceStore.digest(data),
                                          cache: StaticOutputCachePolicy.policy(for: file.path))
        }
        let binary = binaryFiles.map { file -> StaticOutputFileRecord in
            StaticOutputFileRecord(path: file.path, bytes: file.contents.count, sha256: ProjectResourceStore.digest(file.contents),
                                   cache: StaticOutputCachePolicy.policy(for: file.path))
        }
        version = StaticOutputManifest.currentVersion
        files = (text + binary).sorted { $0.path < $1.path }
    }

    init(plan: LocalStaticBuildPlan) {
        self.init(files: plan.files, binaryFiles: plan.binaryFiles)
    }

    /// Deterministic one-line JSON (sorted keys) followed by a newline.
    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    /// SF-1206-004: paths that are missing, extra or changed in `plan` compared with this manifest.
    func mismatchedPaths(in plan: LocalStaticBuildPlan) -> [String] {
        let current = Dictionary(StaticOutputManifest(plan: plan).files.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let recorded = Dictionary(files.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        return Set(current.keys).union(recorded.keys).filter { current[$0] != recorded[$0] }.sorted()
    }
}

/// SF-1206-004 (ADR-0121): every relative file reference in the build's pages
/// (`src`, `href`, `poster`, `url(…)` in style attributes) and stylesheets
/// (`url(…)`) must name a file the build writes. Addresses with a scheme,
/// `//` or `/` (site-root addresses such as canonical links) and fragments
/// alone are not checked.
enum StaticOutputReferenceAudit {
    /// Referencing file → number of references that name no written file.
    static func unresolved(in plan: LocalStaticBuildPlan) -> [String: Int] {
        let written = Set(plan.files.map(\.path) + plan.binaryFiles.map(\.path))
        var result: [String: Int] = [:]
        for file in plan.files where file.path.hasSuffix(".html") || file.path.hasSuffix(".css") {
            let directory = file.path.split(separator: "/").dropLast().map(String.init)
            let missing = references(in: file.contents, isStylesheet: file.path.hasSuffix(".css"))
                .filter { !resolves($0, from: directory, written: written) }.count
            if missing > 0 { result[file.path] = missing }
        }
        return result
    }

    static func references(in text: String, isStylesheet: Bool) -> [String] {
        guard !isStylesheet else { return urls(in: text) }
        var values: [String] = []
        for marker in [" src=\"", " href=\"", " poster=\""] { values += attributeValues(marker, in: text) }
        for style in attributeValues(" style=\"", in: text) { values += urls(in: decodeEntities(style)) }
        return values
    }

    static func resolves(_ rawValue: String, from directory: [String], written: Set<String>) -> Bool {
        var value = decodeEntities(rawValue).trimmingCharacters(in: .whitespaces)
        if let cut = value.firstIndex(where: { $0 == "?" || $0 == "#" }) { value = String(value[..<cut]) }
        guard !value.isEmpty, !value.hasPrefix("/"), !hasScheme(value) else { return true }
        value = value.removingPercentEncoding ?? value
        var components = directory
        for part in value.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            switch part {
            case "", ".":
                continue
            case "..":
                guard !components.isEmpty else { return false }
                components.removeLast()
            default:
                components.append(part)
            }
        }
        let path = components.joined(separator: "/")
        if path.isEmpty { return written.contains("index.html") }
        if value.hasSuffix("/") { return written.contains(path + "/index.html") }
        return written.contains(path)
    }

    private static func attributeValues(_ marker: String, in text: String) -> [String] {
        var values: [String] = []
        var searchStart = text.startIndex
        while let range = text.range(of: marker, range: searchStart..<text.endIndex) {
            guard let end = text[range.upperBound...].firstIndex(of: "\"") else { break }
            values.append(String(text[range.upperBound..<end]))
            searchStart = end
        }
        return values
    }

    private static func urls(in css: String) -> [String] {
        var values: [String] = []
        var searchStart = css.startIndex
        while let range = css.range(of: "url(", range: searchStart..<css.endIndex) {
            guard let end = css[range.upperBound...].firstIndex(of: ")") else { break }
            var value = String(css[range.upperBound..<end]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            values.append(value)
            searchStart = end
        }
        return values
    }

    private static func hasScheme(_ value: String) -> Bool {
        guard let colon = value.firstIndex(of: ":") else { return false }
        let scheme = value[..<colon]
        guard let first = scheme.first, first.isASCII, first.isLetter else { return false }
        return scheme.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == ".") }
    }

    private static func decodeEntities(_ value: String) -> String {
        value.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

// MARK: - SF-1208/SF-1211 build settings, per-file report and budgets (OD-042, ADR-0122)

/// SF-1208-003 / SF-1211-003 (ADR-0122): the effective build settings for one
/// check, each with the rule that supplied it. Built from the immutable
/// document the check consumes, so a preflight and its findings always agree.
struct BuildSettingsResolution: Equatable, Sendable {
    let profile: ProjectPreferenceResolution<LocalBuildProfile>
    let pageBudget: ProjectPreferenceResolution<Int>
    let assetBudget: ProjectPreferenceResolution<Int>
    let totalBudget: ProjectPreferenceResolution<Int>
    let releasePolicy: ProjectPreferenceResolution<BuildReleasePolicy>

    init(_ settings: BuildProfileSettings?) {
        profile = BuildSettingsResolver.profile(settings)
        pageBudget = BuildSettingsResolver.budget(.page, settings)
        assetBudget = BuildSettingsResolver.budget(.asset, settings)
        totalBudget = BuildSettingsResolver.budget(.total, settings)
        releasePolicy = BuildSettingsResolver.releasePolicy(settings)
    }

    init(document: CanonicalDocument) { self.init(document.projectPreferences?.build) }

    func budget(_ kind: BuildBudgetKind) -> ProjectPreferenceResolution<Int> {
        switch kind {
        case .page: pageBudget
        case .asset: assetBudget
        case .total: totalBudget
        }
    }

    /// SF-1211-003: warnings stop writing only for Static Release under the stricter policy.
    func warningsBlock(_ profile: LocalBuildProfile) -> Bool {
        profile == .staticRelease && releasePolicy.value == .warningsBlockRelease
    }
}

/// SF-1208 (ADR-0122): what kind of file a build writes, for totals and budgets.
enum StaticOutputFileKind: String, CaseIterable, Hashable, Sendable {
    case page, stylesheet, script, asset, siteFile = "site-file"

    static func kind(for path: String) -> StaticOutputFileKind {
        if path.hasPrefix("assets/") { return .asset }
        if path.hasSuffix(".html") { return .page }
        if path.hasSuffix(".css") { return .stylesheet }
        if path.hasSuffix(".js") { return .script }
        return .siteFile
    }

    var title: String {
        switch self {
        case .page: "Pages"
        case .stylesheet: "Stylesheets"
        case .script: "Scripts"
        case .asset: "Assets"
        case .siteFile: "Site files"
        }
    }

    var budget: BuildBudgetKind? {
        switch self {
        case .page: .page
        case .asset: .asset
        case .stylesheet, .script, .siteFile: nil
        }
    }
}

/// SF-1208-003/008 (ADR-0122): the per-file build report Check Website shows,
/// built only from `LocalBuildReport.outputFiles` (paths, sizes and cache
/// policies). It holds no file contents.
struct StaticBuildOutputSummary: Equatable, Sendable {
    struct Row: Identifiable, Equatable, Sendable {
        let path: String
        let kind: StaticOutputFileKind
        let bytes: Int
        let cache: StaticOutputCachePolicy
        let exceedsBudget: Bool

        var id: String { path }
        var sizeLabel: String { StaticBuildOutputSummary.sizeLabel(bytes) }
        var cacheLabel: String { cache == .immutable ? "Cache forever" : "Revalidate" }
        var accessibilityDescription: String {
            "\(path), \(sizeLabel), \(cacheLabel)" + (exceedsBudget ? ", over budget" : "")
        }
    }

    struct Total: Equatable, Sendable {
        let kind: StaticOutputFileKind
        let count: Int
        let bytes: Int

        var summary: String { "\(kind.title): \(count) file(s), \(StaticBuildOutputSummary.sizeLabel(bytes))" }
    }

    let rows: [Row]
    let totals: [Total]
    let totalBytes: Int
    let totalExceedsBudget: Bool

    init(files: [StaticOutputFileRecord], settings: BuildSettingsResolution) {
        let built = files.sorted { $0.path < $1.path }.map { file -> Row in
            let kind = StaticOutputFileKind.kind(for: file.path)
            let limit = kind.budget.map { settings.budget($0).value } ?? 0
            return Row(path: file.path, kind: kind, bytes: file.bytes, cache: file.cache,
                       exceedsBudget: StaticBuildOutputSummary.exceeds(file.bytes, kilobytes: limit))
        }
        rows = built
        totals = StaticOutputFileKind.allCases.compactMap { kind -> Total? in
            let matching = built.filter { $0.kind == kind }
            guard !matching.isEmpty else { return nil }
            return Total(kind: kind, count: matching.count, bytes: matching.reduce(0) { $0 + $1.bytes })
        }
        let sum = built.reduce(0) { $0 + $1.bytes }
        totalBytes = sum
        totalExceedsBudget = StaticBuildOutputSummary.exceeds(sum, kilobytes: settings.budget(.total).value)
    }

    var summary: String {
        "\(rows.count) file(s), \(Self.sizeLabel(totalBytes)) in total"
            + (totalExceedsBudget ? ", over the site budget." : ".")
    }

    /// A budget of 0 means no limit.
    static func exceeds(_ bytes: Int, kilobytes: Int) -> Bool { kilobytes > 0 && bytes > kilobytes * 1_024 }

    /// The smallest whole-kilobyte budget that `bytes` fits.
    static func fittingKilobytes(_ bytes: Int) -> Int { max(1, (bytes + 1_023) / 1_024) }

    /// The smallest budget that clears every overage of `kind`; nil when nothing is over.
    func kilobytesToFit(_ kind: BuildBudgetKind) -> Int? {
        switch kind {
        case .total:
            return totalExceedsBudget ? Self.fittingKilobytes(totalBytes) : nil
        case .page, .asset:
            let largest = rows.filter { $0.kind.budget == kind && $0.exceedsBudget }.map(\.bytes).max()
            return largest.map { Self.fittingKilobytes($0) }
        }
    }

    /// Binary units (1 KB = 1,024 bytes), matching the budgets.
    static func sizeLabel(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }
}

/// SF-1211-003/004 (ADR-0122): size budgets and the release policy. Every
/// budget finding names the output file and, where one exists, the object
/// that shows it; findings carry sizes and budgets, never file contents or
/// names the author typed.
enum StaticBuildBudgetAudit {
    static func findings(summary: StaticBuildOutputSummary, settings: BuildSettingsResolution,
                         affectedNodes: [String: NodeID] = [:]) -> [StaticBuildFinding] {
        var findings: [StaticBuildFinding] = []
        for row in summary.rows where row.exceedsBudget {
            guard let kind = row.kind.budget else { continue }
            let limit = BuildSettingsResolver.budgetLabel(settings.budget(kind).value)
            let isPage = kind == .page
            findings.append(.init(severity: .warning, code: kind.findingCode, requirementID: "SF-1211-003",
                affectedNodeID: affectedNodes[row.path], outputPath: row.path,
                explanation: isPage
                    ? "This page is \(row.sizeLabel), over the \(limit) page budget."
                    : "This file is \(row.sizeLabel), over the \(limit) asset budget.",
                repair: isPage
                    ? "Split the page or remove content from it, or raise the page budget in Build Settings."
                    : "Replace the file with a smaller or compressed version, or raise the asset budget in Build Settings."))
        }
        if summary.totalExceedsBudget {
            let limit = BuildSettingsResolver.budgetLabel(settings.totalBudget.value)
            findings.append(.init(severity: .warning, code: BuildBudgetKind.total.findingCode, requirementID: "SF-1211-003",
                explanation: "The website is \(StaticBuildOutputSummary.sizeLabel(summary.totalBytes)), over the \(limit) site budget.",
                repair: "Remove pages or large files the site does not need, or raise the site budget in Build Settings."))
        }
        return findings
    }

    /// SF-1211-003: one blocking finding when the release policy stops Static
    /// Release while warnings remain. Development is never blocked by warnings.
    static func releasePolicyFinding(findings: [StaticBuildFinding], profile: LocalBuildProfile,
                                     settings: BuildSettingsResolution) -> StaticBuildFinding? {
        guard settings.warningsBlock(profile) else { return nil }
        let warnings = findings.filter { $0.severity == .warning }.count
        guard warnings > 0 else { return nil }
        return .init(severity: .error, code: "release-policy-warnings", requirementID: "SF-1211-003",
            explanation: "This project's release policy stops Static Release while warnings remain (\(warnings)). No files are written.",
            repair: "Repair the warnings, choose the Development profile, or choose Block on errors only in Build Settings.")
    }
}

/// SF-1211-002/004 (ADR-0122): a one-step repair Check Website offers beside a
/// finding. Settings repairs commit one undoable project-preferences edit;
/// choosing a profile changes only the current check.
enum StaticBuildRepairAction: Equatable, Sendable {
    case raiseBudget(BuildBudgetKind, kilobytes: Int)
    case allowWarnings
    case useProfile(LocalBuildProfile)
    /// SF-1107-004 / SF-1211-003 (OD-041, ADR-0037 amendment): records that the
    /// custom code with this digest was reviewed. The digest is the one the check
    /// saw, so code changed since then is never acknowledged by this action.
    case acknowledgeCustomCode(digest: String)

    var title: String {
        switch self {
        case .raiseBudget(let kind, let kilobytes): "Raise \(kind.title) to \(BuildSettingsResolver.budgetLabel(kilobytes))"
        case .allowWarnings: "Block on Errors Only"
        case .useProfile(let profile): "Check with \(profile.title)"
        case .acknowledgeCustomCode: "Mark Custom Code as Reviewed"
        }
    }

    var hint: String {
        switch self {
        case .raiseBudget, .allowWarnings: "Saves this build setting in the project. Undo restores the previous value."
        case .useProfile: "Checks the website again with this profile. The project is not changed."
        case .acknowledgeCustomCode:
            "Saves in the project that you reviewed this custom code, so its warnings no longer stop Static Release. Changing the code ends the review; Undo removes it."
        }
    }

    /// Stable, value-free part of the accessibility identifier.
    var identifier: String {
        switch self {
        case .raiseBudget(let kind, _): "raise-\(kind.rawValue)-budget"
        case .allowWarnings: "allow-warnings"
        case .useProfile(let profile): "use-\(profile.rawValue)"
        case .acknowledgeCustomCode: "acknowledge-custom-code"
        }
    }

    /// `customCodeDigest` is `CustomCodeReview.digest` of the checked document;
    /// without it no custom code review is offered.
    static func action(for finding: StaticBuildFinding, report: LocalBuildReport?,
                       settings: BuildSettingsResolution, profile: LocalBuildProfile,
                       customCodeDigest: String? = nil) -> StaticBuildRepairAction? {
        switch finding.code {
        case "release-policy-warnings":
            return .allowWarnings
        case "custom-code-unvalidated":
            // Reviewed code is reported as information and needs no repair.
            guard finding.severity == .warning, let customCodeDigest else { return nil }
            return .acknowledgeCustomCode(digest: customCodeDigest)
        case "css-optimization-skipped":
            return profile == .development ? nil : .useProfile(.development)
        default:
            guard let kind = BuildBudgetKind.allCases.first(where: { $0.findingCode == finding.code }),
                  let report else { return nil }
            let summary = StaticBuildOutputSummary(files: report.outputFiles, settings: settings)
            guard let kilobytes = summary.kilobytesToFit(kind), BuildProfileSettings.isValidBudget(kilobytes) else { return nil }
            return .raiseBudget(kind, kilobytes: kilobytes)
        }
    }
}

/// SF-1208-008 / SF-1211-008 (ADR-0122): value-free record of one build-settings
/// operation: requirement IDs, operation, sanitized document identity, stable
/// setting identities, duration and failure category.
struct BuildSettingsDiagnostic: Equatable, Sendable {
    let requirementIDs: [String]
    let operation: String
    let sanitizedDocumentID: String
    let settingIDs: [String]
    let durationMilliseconds: Int
    let failureCategory: String
}

// MARK: - SF-1208/SF-1211 profile comparison, rebuild changes, browser support (OD-042, ADR-0123, OD-121)

/// SF-1208-003 (ADR-0123): the Development and Static Release output of one
/// check, file by file. Built from both profiles' output records (paths, sizes
/// and SHA-256 hashes), never from file contents.
struct StaticBuildProfileComparison: Equatable, Sendable {
    enum Difference: String, Equatable, Sendable {
        case identical
        case changed
        case onlyDevelopment = "only-development"
        case onlyStaticRelease = "only-static-release"
    }

    struct Row: Identifiable, Equatable, Sendable {
        let path: String
        let developmentBytes: Int?
        let staticReleaseBytes: Int?
        let difference: Difference

        var id: String { path }
        var accessibilityDescription: String {
            let development = developmentBytes.map { StaticBuildOutputSummary.sizeLabel($0) } ?? "not written"
            let release = staticReleaseBytes.map { StaticBuildOutputSummary.sizeLabel($0) } ?? "not written"
            return "\(path): Development \(development), Static Release \(release)"
        }
    }

    let rows: [Row]
    let developmentBytes: Int
    let staticReleaseBytes: Int

    init(development: [StaticOutputFileRecord], staticRelease: [StaticOutputFileRecord]) {
        let developmentFiles = Dictionary(development.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let releaseFiles = Dictionary(staticRelease.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        rows = Set(developmentFiles.keys).union(releaseFiles.keys).sorted().map { path -> Row in
            let developmentFile = developmentFiles[path]
            let releaseFile = releaseFiles[path]
            let difference: Difference
            if let developmentFile, let releaseFile {
                difference = developmentFile.sha256 == releaseFile.sha256 && developmentFile.bytes == releaseFile.bytes
                    ? .identical : .changed
            } else {
                difference = developmentFile == nil ? .onlyStaticRelease : .onlyDevelopment
            }
            return Row(path: path, developmentBytes: developmentFile?.bytes, staticReleaseBytes: releaseFile?.bytes,
                       difference: difference)
        }
        developmentBytes = development.reduce(0) { $0 + $1.bytes }
        staticReleaseBytes = staticRelease.reduce(0) { $0 + $1.bytes }
    }

    var differingRows: [Row] { rows.filter { $0.difference != .identical } }

    var summary: String {
        let developmentCount = rows.filter { $0.developmentBytes != nil }.count
        let releaseCount = rows.filter { $0.staticReleaseBytes != nil }.count
        let differing = differingRows.count
        return "Static Release writes \(releaseCount) file(s), \(StaticBuildOutputSummary.sizeLabel(staticReleaseBytes)); "
            + "Development writes \(developmentCount) file(s), \(StaticBuildOutputSummary.sizeLabel(developmentBytes)). "
            + "\(differing) file(s) differ, \(rows.count - differing) identical."
    }
}

/// SF-1208 (ADR-0123): what a rebuild changes compared with the previous check
/// of the same project and profile. Each file's SHA-256 is its cache key: a
/// file whose key is unchanged is byte-identical, so a host or browser may keep
/// its copy. Writing still produces a complete, verified build (ADR-0123).
struct StaticOutputChangeSummary: Equatable, Sendable {
    let added: [String]
    let changed: [String]
    let removed: [String]
    let unchangedCount: Int

    init(previous: [StaticOutputFileRecord], current: [StaticOutputFileRecord]) {
        let before = Dictionary(previous.map { ($0.path, $0.sha256) }, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(current.map { ($0.path, $0.sha256) }, uniquingKeysWith: { first, _ in first })
        let addedPaths = after.keys.filter { before[$0] == nil }.sorted()
        let changedPaths = after.keys.filter { before[$0] != nil && before[$0] != after[$0] }.sorted()
        added = addedPaths
        changed = changedPaths
        removed = before.keys.filter { after[$0] == nil }.sorted()
        unchangedCount = after.count - addedPaths.count - changedPaths.count
    }

    var isUnchanged: Bool { added.isEmpty && changed.isEmpty && removed.isEmpty }

    var summary: String {
        isUnchanged
            ? "Since the previous check, no file changed (\(unchangedCount) unchanged)."
            : "Since the previous check: \(changed.count) changed, \(added.count) added, \(removed.count) removed, \(unchangedCount) unchanged."
    }
}

/// SF-1211-003 (ADR-0123, OD-121): one browser version, compared numerically.
struct StaticBrowserVersion: Comparable, Hashable, Sendable {
    let major: Int
    let minor: Int

    init(_ major: Int, _ minor: Int = 0) {
        self.major = major
        self.minor = minor
    }

    static func < (lhs: StaticBrowserVersion, rhs: StaticBrowserVersion) -> Bool {
        (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
    }

    var label: String { minor == 0 ? "\(major)" : "\(major).\(minor)" }
}

/// SF-1211-003 (OD-121, approved 2026-11-26; its recommended default): the browsers Check
/// Website grades the output for, each with the oldest version it must serve.
/// The default is every engine's release from the end of 2023.
enum StaticBrowserTarget: String, CaseIterable, Identifiable, Sendable {
    case safari, chrome, edge, firefox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .edge: "Edge"
        case .firefox: "Firefox"
        }
    }

    var minimumVersion: StaticBrowserVersion {
        switch self {
        case .safari: StaticBrowserVersion(17)
        case .chrome, .edge: StaticBrowserVersion(120)
        case .firefox: StaticBrowserVersion(121)
        }
    }

    var label: String { "\(title) \(minimumVersion.label)" }
}

/// SF-1211-003 (ADR-0123): modern features SiteForge's own output uses, each
/// with the fallback the generator already writes for browsers without it.
enum StaticOutputFeature: String, CaseIterable, Identifiable, Sendable {
    case containerQueries = "container-queries"
    case backdropBlur = "backdrop-blur"
    case menuPanelLayout = "menu-panel-layout"
    case revealOnScroll = "reveal-on-scroll"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .containerQueries: "Container size rules"
        case .backdropBlur: "Glass blur"
        case .menuPanelLayout: "Menu panel layout"
        case .revealOnScroll: "Reveal on scroll"
        }
    }

    /// First release of each engine that supports the feature as SiteForge writes it.
    func firstSupportedVersion(_ target: StaticBrowserTarget) -> StaticBrowserVersion {
        switch (self, target) {
        case (.containerQueries, .safari): StaticBrowserVersion(16)
        case (.containerQueries, .chrome), (.containerQueries, .edge): StaticBrowserVersion(105)
        case (.containerQueries, .firefox): StaticBrowserVersion(110)
        // Written with and without the -webkit- prefix.
        case (.backdropBlur, .safari): StaticBrowserVersion(9)
        case (.backdropBlur, .chrome): StaticBrowserVersion(76)
        case (.backdropBlur, .edge): StaticBrowserVersion(79)
        case (.backdropBlur, .firefox): StaticBrowserVersion(103)
        // `::details-content`, guarded by `@supports selector(…)`.
        case (.menuPanelLayout, .safari): StaticBrowserVersion(18, 4)
        case (.menuPanelLayout, .chrome), (.menuPanelLayout, .edge): StaticBrowserVersion(131)
        case (.menuPanelLayout, .firefox): StaticBrowserVersion(143)
        // `IntersectionObserver`, which the runtime checks before use.
        case (.revealOnScroll, .safari): StaticBrowserVersion(12, 1)
        case (.revealOnScroll, .chrome): StaticBrowserVersion(58)
        case (.revealOnScroll, .edge): StaticBrowserVersion(79)
        case (.revealOnScroll, .firefox): StaticBrowserVersion(55)
        }
    }

    /// What visitors see where the feature is missing; SiteForge writes this fallback itself.
    var degradation: String {
        switch self {
        case .containerQueries: "Container size rules are skipped, so objects keep their page-width layout."
        case .backdropBlur: "Glass surfaces show their solid fallback color instead of the blur."
        case .menuPanelLayout: "The open menu uses SiteForge's fallback panel position; its links and keyboard use are the same."
        case .revealOnScroll: "Content is shown at once, without the entrance animation."
        }
    }

    /// Whether the output uses the feature. Only generated stylesheets and
    /// scripts are read; custom code is inline in pages and never graded.
    func isUsed(stylesheets: String, scripts: String) -> Bool {
        switch self {
        case .containerQueries: stylesheets.contains("@container")
        case .backdropBlur: stylesheets.contains("backdrop-filter")
        case .menuPanelLayout: stylesheets.contains("::details-content")
        case .revealOnScroll: scripts.contains("IntersectionObserver")
        }
    }
}

/// SF-1211-003 (ADR-0123, OD-121): the browser target matrix of one check.
/// Every feature the output uses is graded per target; a target older than
/// the feature's first supporting version gets the generator's chosen
/// degradation. No feature is unsupported: each one has a written fallback.
struct StaticBrowserSupportReport: Equatable, Sendable {
    enum Grade: String, Equatable, Sendable {
        case full, degraded

        var title: String { self == .full ? "Full support" : "Works, with fallbacks" }
    }

    struct Entry: Identifiable, Equatable, Sendable {
        let feature: StaticOutputFeature
        /// Targets that get the fallback, in target order.
        let degradedTargets: [StaticBrowserTarget]

        var id: String { feature.rawValue }

        var summary: String {
            guard !degradedTargets.isEmpty else { return "\(feature.title): supported by every target." }
            return "\(feature.title): fallback in " + degradedTargets.map(\.label).joined(separator: ", ")
                + ". " + feature.degradation
        }
    }

    let targets: [StaticBrowserTarget]
    let entries: [Entry]

    init(plan: LocalStaticBuildPlan, targets: [StaticBrowserTarget] = StaticBrowserTarget.allCases) {
        let stylesheets = plan.files.filter { $0.path.hasSuffix(".css") }.map(\.contents).joined(separator: "\n")
        let scripts = plan.files.filter { $0.path.hasSuffix(".js") }.map(\.contents).joined(separator: "\n")
        self.targets = targets
        entries = StaticOutputFeature.allCases.filter { $0.isUsed(stylesheets: stylesheets, scripts: scripts) }
            .map { feature in
                Entry(feature: feature,
                      degradedTargets: targets.filter { $0.minimumVersion < feature.firstSupportedVersion($0) })
            }
    }

    func grade(for target: StaticBrowserTarget) -> Grade {
        entries.contains { $0.degradedTargets.contains(target) } ? .degraded : .full
    }

    func targetSummary(_ target: StaticBrowserTarget) -> String { "\(target.label): \(grade(for: target).title)" }

    var summary: String {
        let targetList = targets.map(\.label).joined(separator: ", ")
        guard !entries.isEmpty else { return "Checked for \(targetList): no feature needs a fallback." }
        let degraded = targets.filter { grade(for: $0) == .degraded }
        guard !degraded.isEmpty else { return "Checked for \(targetList): full support for every feature this website uses." }
        return "Checked for \(targetList): " + degraded.map(\.label).joined(separator: ", ")
            + " use a fallback for at least one feature; nothing stops working."
    }
}

/// SF-1204-008 / SF-1206-008 / SF-1208-008 / SF-1211-008 (ADR-0123): value-free
/// record of one check: requirement IDs, operation, sanitized document identity,
/// profile, counts and sizes, duration and failure category. It never carries
/// paths, selectors, file contents or names the author typed.
struct StaticOutputDiagnostic: Equatable, Sendable {
    let requirementIDs: [String]
    let operation: String
    let sanitizedDocumentID: String
    let profile: String
    let fileCount: Int
    let totalBytes: Int
    let skippedStylesheetCount: Int
    let unresolvedReferenceFileCount: Int
    let budgetWarningCount: Int
    let durationMilliseconds: Int
    let failureCategory: String

    init(compilation: StaticBuildCompilation, durationMilliseconds: Int, operation: String = "preflight") {
        requirementIDs = ["SF-1204-008", "SF-1206-008", "SF-1208-008", "SF-1211-008"]
        self.operation = operation
        sanitizedDocumentID = DiagnosticStableIdentifier.sanitize(compilation.documentID.description,
                                                                   domain: .staticBuild, kind: "document")
        profile = compilation.profile.rawValue
        let files = compilation.report?.outputFiles ?? []
        fileCount = files.count
        totalBytes = files.reduce(0) { $0 + $1.bytes }
        skippedStylesheetCount = compilation.findings.filter { $0.code == "css-optimization-skipped" }.count
        unresolvedReferenceFileCount = compilation.findings.filter { $0.code == "output-reference-unresolved" }.count
        budgetWarningCount = compilation.findings.filter { $0.code.hasPrefix("budget-") }.count
        self.durationMilliseconds = max(0, durationMilliseconds)
        failureCategory = compilation.findings.contains { $0.code == "cancelled" } ? "cancelled"
            : compilation.canWrite ? "none" : "preflight-blocked"
    }
}

// SF-1208/SF-1211 v1: the profile chosen for one check is an explicit request; the
// project's saved starting profile lives in `BuildProfileSettings` (ADR-0122).
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
    /// SF-1204-003 (ADR-0120): one size report per generated stylesheet.
    var cssReports: [StaticCSSOptimizationReport] = []
    /// SF-1206 (ADR-0121): every written file with its size, hash and cache policy
    /// (in Static Release including `siteforge-integrity.json`, which does not list itself).
    var outputFiles: [StaticOutputFileRecord] = []
}

// MARK: - SF-1205 one content-hashed runtime file in Static Release (OD-042, ADR-0124)

/// SF-1205 (OD-042, ADR-0124): Static Release writes SiteForge's generated
/// runtime (menus, Flow effects, motion, interactions) as one content-addressed
/// script, `siteforge-runtime.<sha256>.js`, instead of one file per runtime.
/// Development and Local Preview keep the readable per-runtime files the planner
/// writes. Each page names the parts it used, so it runs exactly the code it ran
/// before, and each part runs inside its own `try`, so one failing part never
/// stops another (the module's isolation invariant); the error is still reported.
enum StaticRuntimeBundle {
    /// The runtime parts in the order the planner links them on a page.
    static let parts = ["navigation", "effects", "motion", "events"]

    /// The planner's readable file for one part (`siteforge-<part>.js`).
    static func sourcePath(_ part: String) -> String { "siteforge-\(part).js" }

    /// The script tag the planner writes for one part on a page `prefix` folders deep.
    static func sourceTag(_ part: String, prefix: String) -> String {
        "<script src=\"\(prefix)\(sourcePath(part))\" defer></script>"
    }

    /// Named by its SHA-256: identical text keeps its name, any changed byte gets a new one.
    static func path(for javascript: String) -> String {
        "siteforge-runtime.\(ProjectResourceStore.digest(Data(javascript.utf8))).js"
    }

    static func isBundlePath(_ path: String) -> Bool {
        path.range(of: "^siteforge-runtime\\.[a-f0-9]{64}\\.js$", options: .regularExpression) != nil
    }

    /// The bundle text for the given parts, in `parts` order. Every part is
    /// fixed SiteForge code already wrapped in its own function, so wrapping it
    /// once more changes neither its scope nor its strict mode.
    static func bundleText(_ sources: [(part: String, javascript: String)]) -> String {
        let header = [
            "/* SiteForge runtime (OD-042, ADR-0124). A page names the parts it uses in data-siteforge-runtime;",
            "   each part runs on its own, so one failing part never stops another. */",
            "(() => {",
            "  const script = document.currentScript;",
            "  const parts = new Set(((script && script.getAttribute('data-siteforge-runtime')) || '').split(' '));",
            "  const run = (name, part) => {",
            "    if (!parts.has(name)) return;",
            "    try { part(); } catch (error) { if (typeof reportError === 'function') reportError(error); else setTimeout(() => { throw error; }); }",
            "  };",
        ]
        let body = sources.map { source in "  run('\(source.part)', () => {\n\(source.javascript)\n  });" }
        return (header + body + ["})();", ""]).joined(separator: "\n")
    }

    /// Static Release: replaces the planner's per-runtime files with one
    /// bundle, points every page that used one at it from the page's own folder
    /// (language trees, collection item and list pages, nested routes) and lists
    /// it in `manifest.txt` instead of the files it replaces. A plan without
    /// runtime files is returned unchanged.
    static func bundle(_ files: [LocalStaticBuildPlan.File]) -> [LocalStaticBuildPlan.File] {
        let sources = parts.compactMap { part -> (part: String, javascript: String)? in
            guard let file = files.first(where: { $0.path == sourcePath(part) }) else { return nil }
            return (part: part, javascript: file.contents)
        }
        guard !sources.isEmpty else { return files }
        let text = bundleText(sources)
        let bundlePath = path(for: text)
        let available = sources.map { $0.part }
        let replaced = Set(available.map { sourcePath($0) })
        var result = files.filter { !replaced.contains($0.path) }.map { file -> LocalStaticBuildPlan.File in
            if file.path == "manifest.txt" {
                let listed = file.contents.split(separator: "\n").map(String.init).filter { !replaced.contains($0) }
                return LocalStaticBuildPlan.File(path: file.path, contents: (listed + [bundlePath]).sorted().joined(separator: "\n"))
            }
            guard file.path.hasSuffix(".html") else { return file }
            return LocalStaticBuildPlan.File(path: file.path,
                contents: page(file.contents, path: file.path, parts: available, bundlePath: bundlePath))
        }
        result.append(LocalStaticBuildPlan.File(path: bundlePath, contents: text))
        return result
    }

    /// One page: the first runtime tag it has becomes the bundle tag, which
    /// names every part the page used; the page's other runtime tags are removed.
    static func page(_ html: String, path: String, parts available: [String], bundlePath: String) -> String {
        let prefix = String(repeating: "../", count: max(0, path.split(separator: "/").count - 1))
        let used = available.filter { html.contains(sourceTag($0, prefix: prefix)) }
        guard let first = used.first, let range = html.range(of: sourceTag(first, prefix: prefix)) else { return html }
        let tag = "<script src=\"\(prefix)\(bundlePath)\" data-siteforge-runtime=\"\(used.joined(separator: " "))\" defer></script>"
        func removingTags(_ text: Substring) -> String {
            used.reduce(String(text)) { result, part in result.replacingOccurrences(of: sourceTag(part, prefix: prefix), with: "") }
        }
        return removingTags(html[..<range.lowerBound]) + tag + removingTags(html[range.upperBound...])
    }
}

enum LocalBuildProfileCompiler {
    /// SF-1204 (ADR-0120): Development writes stylesheets exactly as generated
    /// (readable); Static Release minifies them and removes only rules that
    /// cannot change the result (see `StaticCSSOptimizer`).
    static func compile(_ plan: LocalStaticBuildPlan, profile: LocalBuildProfile) -> (LocalStaticBuildPlan, LocalBuildReport) {
        // SF-1205 (OD-042, ADR-0124): Static Release writes the generated runtime as
        // one content-addressed script; Development keeps the readable per-runtime files.
        let sourceFiles = profile == .staticRelease ? StaticRuntimeBundle.bundle(plan.files) : plan.files
        let usedIdentifiers: Set<String> = profile == .staticRelease
            ? StaticCSSOptimizer.usedIdentifiers(in: sourceFiles.filter { $0.path.hasSuffix(".html") || $0.path.hasSuffix(".js") }.map(\.contents))
            : []
        var cssReports: [StaticCSSOptimizationReport] = []
        let files = sourceFiles.sorted { $0.path < $1.path }.map { file -> LocalStaticBuildPlan.File in
            guard file.path.hasSuffix(".css") else { return LocalStaticBuildPlan.File(path: file.path, contents: file.contents) }
            switch profile {
            case .development:
                cssReports.append(.readable(path: file.path, css: file.contents))
                return LocalStaticBuildPlan.File(path: file.path, contents: file.contents)
            case .staticRelease:
                let optimized = StaticCSSOptimizer.optimize(file.contents, path: file.path, usedIdentifiers: usedIdentifiers)
                cssReports.append(optimized.report)
                return LocalStaticBuildPlan.File(path: file.path, contents: optimized.css)
            }
        }
        // SF-1206 (ADR-0121): Static Release also writes the integrity manifest of every other file.
        let binaryFiles = plan.binaryFiles.sorted { $0.path < $1.path }
        let manifest = StaticOutputManifest(files: files, binaryFiles: binaryFiles)
        var outputFiles = files
        // The report lists every written file, the integrity manifest included,
        // so Output files and the site budget count exactly what is written.
        var records = manifest.files
        if profile == .staticRelease {
            let manifestJSON = manifest.json
            outputFiles = files.filter { $0.path != StaticOutputManifest.fileName }
                + [LocalStaticBuildPlan.File(path: StaticOutputManifest.fileName, contents: manifestJSON)]
            outputFiles.sort { $0.path < $1.path }
            let manifestData = Data(manifestJSON.utf8)
            records.append(StaticOutputFileRecord(path: StaticOutputManifest.fileName, bytes: manifestData.count,
                sha256: ProjectResourceStore.digest(manifestData), cache: .revalidate))
            records.sort { $0.path < $1.path }
        }
        return (.init(revision: plan.revision, files: outputFiles, binaryFiles: binaryFiles),
                .init(revision: plan.revision, profile: profile,
                      filePaths: (outputFiles.map(\.path) + binaryFiles.map(\.path)).sorted(),
                      deferredCapabilities: ["publishing", "remote-runtime"], cssReports: cssReports,
                      outputFiles: records))
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
    /// SF-1208-003 (ADR-0122, ADR-0123): the build settings this check used, so its
    /// per-file report and repairs agree with its findings even after Undo.
    var buildSettings: BuildSettingsResolution? = nil
    /// SF-1208-003 (ADR-0123): Development and Static Release output, file by file.
    var profileComparison: StaticBuildProfileComparison? = nil
    /// SF-1211-003 (ADR-0123, OD-121): browser targets and the output's chosen degradations.
    var browserSupport: StaticBrowserSupportReport? = nil

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
                        package: ProjectPackage, includesCustomCode: Bool = true) -> StaticBuildCompilation {
        do {
            let input = try ProjectImageResourceSnapshot(document: document, package: package)
            return compile(document: document, profileSelection: profileSelection,
                resourceDescriptors: input.descriptors, resourceData: input.data, cancelled: Task.isCancelled,
                includesCustomCode: includesCustomCode)
        } catch is CancellationError {
            return compile(document: document, profileSelection: profileSelection,
                resourceDescriptors: [:], resourceData: [:], cancelled: true, includesCustomCode: includesCustomCode)
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
        cancelled: Bool = false,
        includesCustomCode: Bool = true
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
        let websitePages = document.websitePages
        for page in websitePages {
            do { _ = try DecorativeEffectOutput.configurations(page) }
            catch {
                findings.append(.init(severity: .error, code: "flow-configuration-unavailable",
                    requirementID: "SF-1101-004", explanation: error.localizedDescription,
                    repair: "Restore a supported single gradient fill or disable Flow. Use at most four enabled effects per page."))
            }
        }
        // OD-039 / SF-1101: missing interaction targets, pointer-only interactions and focus loops.
        let websitePageIDs = Set(websitePages.map(\.id))
        for original in websitePages {
            // Component instances are expanded first, as for page-flow checks above,
            // so interactions and overlays inside instances are checked too.
            let page = (try? ComponentGraphResolver.resolvedPage(original, in: document, breakpoint: .desktop)) ?? original
            findings += EventGraphOutput.findings(page, availablePageIDs: websitePageIDs)
            let failures = CanonicalPageFlow.outputFailures(page, availablePageIDs: websitePageIDs)
            for id in failures.keys.sorted(by: { $0.description < $1.description }) {
                guard let failure = failures[id] else { continue }
                findings.append(.init(severity: .error, code: failure.code,
                    requirementID: "SF-0501-004", affectedNodeID: id,
                    explanation: failure.explanation, repair: failure.repair))
            }
        }
        // OD-034: instances inside definitions that a website page uses are
        // output too, so they are checked exactly like page instances.
        for instance in CanonicalComponentGraph.outputInstances(in: document) {
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
        // SF-1003: item pages and list copies show each item's own image; export those too.
        let itemNodes = CollectionTemplates.outputPages(websitePages, document: document)
            .filter { $0.itemID != nil || $0.listPageNumber != nil }.flatMap(\.page.nodes)
        let outputNodes = nodes + itemNodes
        var firstImageUse: [AssetID: NodeID] = [:]
        for node in nodes {
            if let assetID = referencedAssetID(node), firstImageUse[assetID] == nil {
                firstImageUse[assetID] = node.id
            }
        }
        // OD-038: images only a translation shows are written with the site too.
        var referencedAssetIDs = SiteLanguageOutput.translatedAssetIDs(document)
        referencedAssetIDs.formUnion(firstImageUse.keys)
        referencedAssetIDs.formUnion(itemNodes.lazy.compactMap(referencedAssetID))
        if let favicon = document.websiteMetadata?.faviconAssetID { referencedAssetIDs.insert(favicon) }
        if let social = document.websiteMetadata?.socialImageAssetID { referencedAssetIDs.insert(social) }
        let referencedAssets = document.imageAssets.filter { asset in
            referencedAssetIDs.contains(asset.id)
        }.sorted { $0.id.description < $1.id.description }
        var entries: [StaticAssetExportEntry] = []
        var binaries: [LocalStaticBuildPlan.BinaryFile] = []
        if let favicon = document.websiteMetadata?.faviconAssetID,
           !document.imageAssets.contains(where: { $0.id == favicon }) {
            findings.append(.init(severity: .error, code: "favicon-missing",
                requirementID: "SF-1207-004", explanation: "The website favicon is unavailable.",
                repair: "Choose a replacement image or remove the favicon in Site Settings."))
        }
        if let social = document.websiteMetadata?.socialImageAssetID,
           !document.imageAssets.contains(where: { $0.id == social }) {
            findings.append(.init(severity: .error, code: "social-image-missing",
                requirementID: "SF-1207-004", explanation: "The website's social image is unavailable.",
                repair: "Choose a replacement image or remove the social image in Website Settings."))
        }
        // SF-0804-004: an SVG social image is exported, but most link previews ignore it.
        if let social = document.websiteMetadata?.socialImageAssetID,
           document.imageAssets.first(where: { $0.id == social })?.format == .svg {
            findings.append(.init(severity: .warning, code: "social-image-svg", requirementID: "SF-0804-004",
                explanation: "The website's social image is an SVG; most link previews show only PNG or JPEG images.",
                repair: "Choose a PNG or JPEG social image in Website Settings."))
        }
        findings += StaticSEOAudit.findings(document: document)
        findings += customCodeFindings(document: document, included: includesCustomCode)
        findings += SiteLanguageOutput.findings(document: document)
        // SF-1206-003 (ADR-0121): project files the website does not use are not written; say so once.
        let unusedImageCount = ImageAssetDependencies.unusedAssetIDs(in: document).count
        let unusedFontCount = document.fontAssets.filter { !ProjectFontOutput.isUsed($0.family, in: document) }.count
        // SF-0803: video, audio and captions no Image plays are not written either.
        let unusedMediaCount = document.mediaAssets.filter { MediaAssetEditing.usageCount($0.id, in: document) == 0 }.count
        if unusedImageCount + unusedFontCount + unusedMediaCount > 0 {
            var unusedParts: [String] = []
            if unusedImageCount > 0 { unusedParts.append("\(unusedImageCount) project image(s)") }
            if unusedFontCount > 0 { unusedParts.append("\(unusedFontCount) project font(s)") }
            if unusedMediaCount > 0 { unusedParts.append("\(unusedMediaCount) video, audio or captions file(s)") }
            findings.append(.init(severity: .information, code: "assets-unused", requirementID: "SF-1206-003",
                explanation: unusedParts.joined(separator: " and ") + " are not used by the website, so they are not written with it.",
                repair: "Nothing is needed. To keep the project small, remove unused items in Assets, Project Fonts or Video & Audio."))
        }
        // SF-1211-003 (ADR-0122): output path → the object that shows it, for budget findings.
        var affectedOutputNodes: [String: NodeID] = [:]
        for asset in referencedAssets {
            let affected = firstImageUse[asset.id]
            guard let descriptor = resourceDescriptors[asset.resourceID],
                  let bytes = resourceData[asset.resourceID] else {
                findings.append(.init(severity: .error, code: "asset-missing",
                    requirementID: "SF-1206-004", affectedNodeID: affected,
                    explanation: "A referenced image resource is unavailable.",
                    repair: "Locate, replace, or detach the missing image in Assets."))
                continue
            }
            if let qrNode = nodes.first(where: { CanonicalImageStyle.resolve($0)?.assetID == asset.id && (try? CanonicalQRCode.resolve($0)) != nil }),
               let code = try? CanonicalQRCode.resolve(qrNode) {
                do { try ProjectQRCodeVerifier.verify(bytes, payload: code.payload) }
                catch {
                    findings.append(.init(severity: .error, code: "qr-payload-mismatch", requirementID: "SF-0802-004", affectedNodeID: qrNode.id,
                        explanation: "Generated QR image bytes do not decode to their retained destination.",
                        repair: "Select the QR Image and regenerate its destination, or convert it to an ordinary Image."))
                    continue
                }
            }
            do {
                let planned = try StaticAssetExportPlanner.plan(
                    index: .init(resources: [descriptor]), blobs: [descriptor.sha256: bytes])
                guard let entry = planned.first, entry.sha256 == asset.contentHash else {
                    throw StaticAssetExportError.corrupt
                }
                entries.append(entry)
                binaries.append(.init(path: entry.outputPath, contents: bytes))
                if let affected { affectedOutputNodes[entry.outputPath] = affected }
            } catch let error as StaticAssetExportError {
                let code: String = switch error {
                case .unsupported: "asset-unsupported"
                case .corrupt: "asset-corrupt"
                case .oversized: "asset-oversized"
                }
                findings.append(.init(severity: error == .unsupported ? .unsupported : .error,
                    code: code, requirementID: "SF-1206-004", affectedNodeID: affected,
                    explanation: error == .oversized ? "A referenced image is larger than the per-file limit, so it cannot be exported."
                        : "A referenced image cannot be exported safely.",
                    repair: error == .oversized ? "Replace the image with a smaller PNG, JPEG or SVG."
                        : "Replace the image with a supported intact PNG, JPEG or SVG."))
            } catch {
                findings.append(.init(severity: .error, code: "asset-invalid",
                    requirementID: "SF-1206-004", affectedNodeID: affected,
                    explanation: "A referenced image failed closed validation.",
                    repair: "Replace or detach the affected image."))
            }
        }
        // OD-045 / SF-0803: video, audio and captions that output Images play.
        findings += ProjectMediaOutput.findings(nodes: outputNodes, document: document)
        var mediaEntries: [StaticAssetExportEntry] = []
        for media in ProjectMediaOutput.exportCandidates(nodes: outputNodes, document: document) {
            let affected = outputNodes.first { ProjectMediaOutput.references(media.id, $0) }?.id
            guard let descriptor = resourceDescriptors[media.resourceID], let bytes = resourceData[media.resourceID] else {
                findings.append(.init(severity: .error, code: "media-missing", requirementID: "SF-0803-004", affectedNodeID: affected,
                    explanation: "A video, audio or captions file that a page plays is missing from the project.",
                    repair: "Replace the file in Video & Audio, or turn off the Image's video or audio in the Inspector."))
                continue
            }
            do {
                let planned = try StaticAssetExportPlanner.plan(
                    index: .init(resources: [descriptor]), blobs: [descriptor.sha256: bytes])
                guard let entry = planned.first, entry.sha256 == media.contentHash else { throw StaticAssetExportError.corrupt }
                mediaEntries.append(entry)
                if let affected { affectedOutputNodes[entry.outputPath] = affected }
                binaries.append(.init(path: entry.outputPath, contents: bytes))
            } catch {
                findings.append(.init(severity: .error, code: "media-invalid", requirementID: "SF-0803-004", affectedNodeID: affected,
                    explanation: "A video, audio or captions file failed its integrity or type check, so it can't be exported.",
                    repair: "Replace the file in Video & Audio with an intact MP4, WebM, MP3, M4A, OGG, WAV or WebVTT file."))
            }
        }
        guard !findings.contains(where: { $0.severity == .error }) else {
            return .init(documentID: document.id, revision: document.revision,
                         profile: profileSelection.profile, plan: nil, report: nil,
                         findings: findings.sorted { $0.id < $1.id })
        }
        // OD-045 / SF-0805: package used faces with declared web rights; a
        // missing or damaged file falls back to the family's stack (warning).
        findings += ProjectFontOutput.findings(document: document)
        var fontEntries: [StaticAssetExportEntry] = []
        for font in ProjectFontOutput.exportCandidates(in: document) {
            guard let descriptor = resourceDescriptors[font.resourceID], let bytes = resourceData[font.resourceID] else {
                findings.append(.init(severity: .warning, code: "font-resource-missing", requirementID: "SF-0805-004",
                    explanation: "A project font file is unavailable, so its text uses the fallback fonts.",
                    repair: "Import the font again in Project Fonts, or remove it."))
                continue
            }
            do {
                let planned = try StaticAssetExportPlanner.plan(
                    index: .init(resources: [descriptor]), blobs: [descriptor.sha256: bytes])
                guard let entry = planned.first, entry.sha256 == font.contentHash else { throw StaticAssetExportError.corrupt }
                fontEntries.append(entry)
                binaries.append(.init(path: entry.outputPath, contents: bytes))
            } catch {
                findings.append(.init(severity: .warning, code: "font-resource-invalid", requirementID: "SF-0805-004",
                    explanation: "A project font file failed its integrity check, so its text uses the fallback fonts.",
                    repair: "Import the font again in Project Fonts, or remove it."))
            }
        }
        do {
            let base = try MultiPageStaticBuildPlanner.plan(document: document, imageOutputEntries: entries,
                                                            includesCustomCode: includesCustomCode, fontOutputEntries: fontEntries,
                                                            mediaOutputEntries: mediaEntries)
            let withAssets = LocalStaticBuildPlan(revision: base.revision, files: base.files,
                binaryFiles: binaries.sorted { $0.path < $1.path })
            let compiled = LocalBuildProfileCompiler.compile(withAssets, profile: profileSelection.profile)
            // SF-1204-004: a stylesheet that cannot be optimized safely is written unchanged and named.
            for cssReport in compiled.1.cssReports where cssReport.skippedReason != nil {
                findings.append(.init(severity: .warning, code: "css-optimization-skipped", requirementID: "SF-1204-004",
                    outputPath: cssReport.path,
                    explanation: "A generated stylesheet could not be optimized safely, so it is written unminified.",
                    repair: "No change is needed; the site looks the same. Choose the Development profile to inspect the readable stylesheet."))
            }
            // SF-1206-004 (ADR-0121): every relative page, image, font, stylesheet and script
            // reference must name a file the build writes.
            let unresolvedReferences = StaticOutputReferenceAudit.unresolved(in: compiled.0)
            for path in unresolvedReferences.keys.sorted() {
                guard let count = unresolvedReferences[path] else { continue }
                findings.append(.init(severity: .warning, code: "output-reference-unresolved", requirementID: "SF-1206-004",
                    outputPath: path,
                    explanation: "\(count) link(s) or file reference(s) in this file name files the build does not write, so they will not load.",
                    repair: "Check this page's links, images and custom code, then check the website again."))
            }
            // SF-1211-003 (ADR-0122): size budgets from the project's build settings.
            let buildSettings = BuildSettingsResolution(document: document)
            findings += StaticBuildBudgetAudit.findings(
                summary: StaticBuildOutputSummary(files: compiled.1.outputFiles, settings: buildSettings),
                settings: buildSettings, affectedNodes: affectedOutputNodes)
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
            // SF-1211-003 (ADR-0122): the configured release policy decides whether warnings block writing.
            if let blocked = StaticBuildBudgetAudit.releasePolicyFinding(findings: findings,
                    profile: profileSelection.profile, settings: buildSettings) {
                findings.append(blocked)
            }
            // SF-1208-003 (ADR-0123): the other profile of the same plan, for the file-by-file comparison.
            let otherProfile: LocalBuildProfile = profileSelection.profile == .development ? .staticRelease : .development
            let otherReport = LocalBuildProfileCompiler.compile(withAssets, profile: otherProfile).1
            let comparison = profileSelection.profile == .development
                ? StaticBuildProfileComparison(development: compiled.1.outputFiles, staticRelease: otherReport.outputFiles)
                : StaticBuildProfileComparison(development: otherReport.outputFiles, staticRelease: compiled.1.outputFiles)
            return .init(documentID: document.id, revision: document.revision,
                         profile: profileSelection.profile, plan: compiled.0, report: compiled.1,
                         findings: findings.sorted { $0.id < $1.id }, buildSettings: buildSettings,
                         profileComparison: comparison, browserSupport: StaticBrowserSupportReport(plan: compiled.0))
        } catch {
            findings.append(.init(severity: .error, code: "plan-invalid",
                requirementID: "SF-1211-004", explanation: "The static plan could not be produced safely.",
                repair: "Review page routes and compatibility findings, then run preflight again."))
            return .init(documentID: document.id, revision: document.revision,
                         profile: profileSelection.profile, plan: nil, report: nil,
                         findings: findings.sorted { $0.id < $1.id })
        }
    }

    /// SF-1107-004: custom code is never checked, so it is always named. The
    /// findings carry no authored text.
    static func customCodeFindings(document: CanonicalDocument, included: Bool) -> [StaticBuildFinding] {
        guard let metadata = document.websiteMetadata, metadata.usesCustomCode else { return [] }
        guard included else {
            return [.init(severity: .information, code: "custom-code-excluded-from-preview", requirementID: "SF-1107-003",
                explanation: "Custom code is not included in Preview or in Export from Preview.",
                repair: "Use Check Website, then Choose Destination and Build, to write a site that includes it.")]
        }
        // ADR-0037 amendment: code the author marked as reviewed is still named,
        // as information, so it no longer stops Static Release under "Block
        // Static Release on warnings". Any change to the code ends the review.
        let review = CustomCodeReview.status(document)
        let severity: StaticBuildFindingSeverity = review == .reviewed ? .information : .warning
        let reviewNote: String = switch review {
        case .reviewed: " It is marked as reviewed in this project, so it does not stop Static Release."
        case .changedSinceReview: " It changed after it was marked as reviewed."
        case .noCustomCode, .notReviewed: ""
        }
        var findings: [StaticBuildFinding] = [.init(severity: severity, code: "custom-code-unvalidated",
            requirementID: "SF-1107-004",
            explanation: "This website includes custom HTML or CSS that SiteForge writes exactly as entered and does not check." + reviewNote,
            repair: review == .reviewed
                ? "Test the built site in each browser you support. Changing the code ends the review."
                : "Review Custom Code in Website Settings and test the built site in each browser you support, then choose Mark Custom Code as Reviewed.")]
        // SF-1107-004 (ADR-0145): one script finding per affected block. Site
        // code has no output path; a page's code is named by its output file.
        var scriptOutputs = Set<String?>()
        if metadata.customCode?.containsScript == true { scriptOutputs.insert(nil) }
        for entry in metadata.pages where entry.customCode?.containsScript == true {
            scriptOutputs.insert(document.pages.first { $0.id == entry.pageID }
                .flatMap { try? MultiPageStaticBuildPlanner.outputPath(for: $0) })
        }
        for outputPath in scriptOutputs.sorted(by: { ($0 ?? "") < ($1 ?? "") }) {
            findings.append(.init(severity: severity, code: "custom-code-script", requirementID: "SF-1107-004",
                outputPath: outputPath,
                explanation: "Custom HTML contains script. It runs in visitors' browsers, never inside SiteForge.",
                repair: "Keep only scripts you trust, or remove them in Website Settings → Custom Code."))
        }
        return findings
    }
}

// SF-1203 v1 output is intentionally in-memory only. The fixed vocabulary and
// allowlist prevent authored content from becoming executable markup.
enum SafeHTMLEmissionError: Error, Equatable, Sendable { case unsupportedTag, invalidIdentity, invalidFormField, invalidControl }

enum SafeHTMLEmitter {
    static func emit(_ tree: InternalRenderTreeSnapshot, layoutContainers: Set<NodeID> = [], flowConfigurations: [NodeID: FlowOutputConfiguration] = [:],
                     entrances: [NodeID: Int] = [:], events: [NodeID: String] = [:], startsHidden: Set<NodeID> = [],
                     attributes extraAttributes: [NodeID: String] = [:],
                     queryWrappers: [NodeID: String] = [:]) throws -> String {
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
                // ADR-0065: a form inside a hidden or revealed container on a static-layout page names it.
                return "<form data-siteforge-node=\"\(identifier)\" class=\"sf-node-\(identifier)\"\(accessibility)\(extraAttributes[node.id] ?? "")>\(fields)</form>"
            }
            var markup = try emitNode(node, formIDs: formIDs, flow: flowConfigurations[node.id], entrance: entrances[node.id],
                                      events: events[node.id], startsHidden: startsHidden.contains(node.id), extra: extraAttributes[node.id] ?? "")
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
        // Lane V19 (ADR-0031): on a page without page flow the contents of a
        // container that rules query are written inside its wrapper
        // (`StaticContainerQueryWrapping.openingTags`), which directly
        // follows the container's own element. Paint order is depth first, so
        // the contents are the elements that follow until one outside it, and
        // the order of every element is unchanged.
        var openWrappers: [NodeID] = []
        func holds(_ container: NodeID, _ node: InternalRenderTreeNode) -> Bool {
            var parent = node.parentNodeID, steps = 0
            while let id = parent, steps <= byID.count {
                if id == container { return true }
                steps += 1
                parent = byID[id]?.parentNodeID
            }
            return false
        }
        for node in ordered where node.formField == nil && node.navigationOwnerID == nil {
            guard try !hasFlowAncestor(node) else { continue }
            while let open = openWrappers.last, !holds(open, node) {
                openWrappers.removeLast()
                fragments.append("</div>")
            }
            fragments.append(try render(node))
            if !structured, let tag = queryWrappers[node.id] {
                openWrappers.append(node.id)
                fragments.append(tag)
            }
        }
        fragments += openWrappers.map { _ in "</div>" }
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

    private static func emitNode(_ node: InternalRenderTreeNode, formIDs: Set<NodeID>, flow: FlowOutputConfiguration? = nil, entrance: Int? = nil,
                                   events: String? = nil, startsHidden: Bool = false, extra: String = "") throws -> String {
        let allowed = Set(["div", "section", "main", "header", "footer", "nav", "article", "aside", "p", "h1", "h2", "h3", "h4", "h5", "h6", "img", "button", "a", "form"])
        guard allowed.contains(node.semanticElement) else { throw SafeHTMLEmissionError.unsupportedTag }
        let identifier = try validatedIdentifier(node)
        if node.formField != nil {
            return try emitField(node, formIDs: formIDs)
        }
        let anchor = node.anchorID.map { " id=\"\(escape($0))\"" } ?? ""
        let flowAttribute = flow.map { " data-siteforge-flow=\"\(escape($0.json))\"" } ?? ""
        // OD-040: the trigger line is a validated whole percent (0...50).
        let entranceAttribute = entrance.map { " data-siteforge-entrance=\"\($0)\"" } ?? ""
        // OD-039: compiled event JSON is escaped here; start-hidden nodes begin with `hidden`.
        let eventAttribute = events.map { " data-siteforge-events=\"\(escape($0))\"" } ?? ""
        let attributes = flowAttribute + entranceAttribute + eventAttribute + " data-siteforge-node=\"\(identifier)\" class=\"sf-node-\(identifier)\"\(anchor)\(accessibilityAttributes(node))"
            + extra + (startsHidden ? " hidden" : "")
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
        if let image = node.image, let media = image.media {
            return emitMedia(media, image: image, node: node, attributes: attributes)
        }
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

    /// OD-045 / SF-0803: the browser's native controls, metadata-only preload
    /// and the original file (no transcoding). Sound never starts by itself:
    /// `autoplay` is written only for muted video. Video uses the Image as
    /// its poster; for audio the Image shows only on the canvas.
    private static func emitMedia(_ media: InternalStaticMedia, image: InternalStaticImage,
                                  node: InternalRenderTreeNode, attributes: String) -> String {
        let element = media.kind == .video ? "video" : "audio"
        var markup = "<\(element)\(attributes) data-siteforge-media=\"\(escape(media.assetID.description))\" controls preload=\"metadata\""
        if media.loops { markup += " loop" }
        if media.isMuted { markup += " muted" }
        if media.kind == .video {
            markup += " playsinline"
            if media.autoplays, media.isMuted { markup += " autoplay" }
            if let poster = image.outputPath, isVerifiedAssetPath(poster) { markup += " poster=\"\(escape(poster))\"" }
        }
        if node.accessibilityName == nil, !image.isDecorative, let label = safeTextContent(image.altText), !label.isEmpty {
            markup += " aria-label=\"\(escape(label))\""
        }
        var children = ""
        if let path = media.outputPath, isVerifiedMediaPath(path) {
            children += "<source src=\"\(escape(path))\" type=\"\(escape(media.mediaType))\">"
        } else {
            markup += " data-siteforge-media-state=\"missing\""
        }
        if media.kind == .video, let captions = media.captionsPath, isVerifiedMediaPath(captions) {
            let language = media.captionsLanguage.map { " srclang=\"\(escape($0))\"" } ?? ""
            let label = media.captionsLabel.flatMap(safeTextContent).map { " label=\"\(escape($0))\"" } ?? ""
            children += "<track kind=\"captions\" src=\"\(escape(captions))\"\(language)\(label) default>"
        }
        children += media.kind == .video ? "Your browser cannot play this video." : "Your browser cannot play this audio."
        return markup + ">" + children + "</\(element)>"
    }

    private static func isVerifiedMediaPath(_ value: String) -> Bool {
        value.range(of: "^assets/[a-f0-9]{64}\\.(mp4|webm|mp3|m4a|ogg|wav|vtt)$", options: .regularExpression) != nil
    }

    private static func isVerifiedAssetPath(_ value: String) -> Bool {
        value.range(of: "^assets/[a-f0-9]{64}\\.(png|jpg|svg)$", options: .regularExpression) != nil
    }

    private static func validOptions(_ options: [InternalFormOption]) -> Bool {
        !options.isEmpty && options.count <= CanonicalFormSelectOptions.maximumOptions &&
        Set(options.map(\.id)).count == options.count && Set(options.map(\.value)).count == options.count &&
        options.allSatisfy { validText($0.label, maximum: CanonicalFormSelectOptions.maximumTextLength) && validText($0.value, maximum: CanonicalFormSelectOptions.maximumTextLength) }
    }

    static func escape(_ value: String) -> String {
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
