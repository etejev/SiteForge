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

struct CanvasTypography: Codable, Hashable, Sendable {
    let authoredFamily: String
    let resolvedFamily: String
    let weight: String
    let size: Double
    let lineHeight: Double
    let tracking: Double
    let alignment: CanvasTextAlignment
    let usesFallback: Bool
    var isValid: Bool {
        !authoredFamily.isEmpty && !resolvedFamily.isEmpty
            && [size, lineHeight, tracking].allSatisfy(\.isFinite)
            && (1...1_000).contains(size) && (1...2_000).contains(lineHeight)
            && lineHeight >= size * 0.5 && (-100...100).contains(tracking)
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
    let frame: WorldRect
    let clipRect: WorldRect?
    let paintOrder: Int
    let style: CanvasPaintStyle
    let isVisible: Bool
    let accessibilityLabel: String
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

    init(
        id: NodeID,
        frame: WorldRect,
        clipRect: WorldRect?,
        paintOrder: Int,
        style: CanvasPaintStyle,
        isVisible: Bool,
        accessibilityLabel: String,
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
        semanticElement: String? = nil
    ) {
        self.id = id
        self.frame = frame
        self.clipRect = clipRect
        self.paintOrder = paintOrder
        self.style = style
        self.isVisible = isVisible
        self.accessibilityLabel = accessibilityLabel
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
    }
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

    init(
        schemaVersion: Int = currentSchemaVersion,
        identity: CanvasRenderRequestIdentity,
        surfaceID: CanvasRenderSurfaceID,
        objects: [CanvasRenderObject]
    ) {
        self.schemaVersion = schemaVersion
        self.identity = identity
        self.surfaceID = surfaceID
        self.objects = objects
    }
}

struct CanvasEditorOverlaySnapshot: Equatable, Sendable {
    let identity: CanvasRenderRequestIdentity
    let overlays: [CanvasEditorOverlay]
}

struct CanvasPreviewSceneSnapshot: Equatable, Sendable {
    let documentID: DocumentID
    let revision: UInt64
    let objects: [CanvasRenderObject]
    let deterministicDigest: String
}

// SF-1202 v1: immutable internal render-tree metadata. This compiler consumes
// an already-adopted scene; it cannot write canonical content or UI state.
struct InternalRenderTreeNode: Equatable, Sendable {
    let id: NodeID
    let sourceNodeID: NodeID
    let paintOrder: Int
    let frame: WorldRect
    let semanticElement: String
    let cssSelector: String
    let formField: InternalFormField?
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
    let nodes: [InternalRenderTreeNode]
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
    static func compile(page: DocumentPage, documentID: DocumentID, revision: UInt64) throws -> InternalRenderTreeSnapshot {
        let nodesByID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let nodes = try page.canonicalDepthFirstNodes().enumerated().map { paintOrder, node in
            let formField = try field(for: node, nodesByID: nodesByID)
            return InternalRenderTreeNode(
                id: node.id, sourceNodeID: node.id, paintOrder: paintOrder,
                frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 0, height: 0)),
                semanticElement: CanonicalSemanticElement.defaultElement(for: node.kind)?.rawValue ?? "div",
                cssSelector: CanonicalCSSRule.selector(for: node.id), formField: formField
            )
        }
        return .init(documentID: documentID, revision: revision, nodes: nodes)
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
            return "[data-siteforge-node=\"\(id)\"] { height: \(f.size.height)px; left: \(f.origin.x)px; position: absolute; top: \(f.origin.y)px; width: \(f.size.width)px; }"
        }.joined(separator: "\n")
        // Fixed output-only control baseline. It neither exposes authored
        // values nor creates a submission path; per-control styling remains
        // deferred until a typed Form-style model exists.
        let controls = tree.nodes.contains { $0.formField != nil } ? "form { font: inherit; } form input, form select, form textarea, form button { box-sizing: border-box; font: inherit; max-width: 100%; } form button[disabled] { cursor: not-allowed; }" : ""
        return [geometry, controls].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

// SF-1206 foundation: build plans are deterministic and side-effect free.
struct LocalStaticBuildPlan: Equatable, Sendable {
    struct File: Equatable, Sendable { let path: String; let contents: String }
    let revision: UInt64
    let files: [File]
}

enum LocalStaticBuildPlanner {
    static func plan(_ tree: InternalRenderTreeSnapshot) throws -> LocalStaticBuildPlan {
        .init(revision: tree.revision, files: [.init(path: "index.html", contents: try SafeHTMLEmitter.emit(tree)), .init(path: "styles.css", contents: try SafeCSSEmitter.emit(tree))])
    }
}

enum LocalStaticBuildWriteError: Error, Equatable, Sendable { case unsafeDestination, stale, cancelled, writeFailed }

enum LocalStaticBuildWriter {
    static func write(_ plan: LocalStaticBuildPlan, to destination: URL, expectedRevision: UInt64, cancelled: Bool = false) throws {
        guard !cancelled else { throw LocalStaticBuildWriteError.cancelled }
        guard plan.revision == expectedRevision else { throw LocalStaticBuildWriteError.stale }
        let target = destination.standardizedFileURL
        guard target.path != "/", !target.path.isEmpty,
              !FileManager.default.fileExists(atPath: target.path) ||
                (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw LocalStaticBuildWriteError.unsafeDestination }
        let parent = target.deletingLastPathComponent()
        let stage = parent.appendingPathComponent(".siteforge-build-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
            for file in plan.files {
                guard !file.path.contains(".."), !file.path.contains("/") else { throw LocalStaticBuildWriteError.unsafeDestination }
                try file.contents.data(using: .utf8)!.write(to: stage.appendingPathComponent(file.path), options: .atomic)
            }
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.moveItem(at: stage, to: target)
        } catch let error as LocalStaticBuildWriteError {
            try? FileManager.default.removeItem(at: stage); throw error
        } catch {
            try? FileManager.default.removeItem(at: stage); throw LocalStaticBuildWriteError.writeFailed
        }
    }
}

enum MultiPageStaticBuildError: Error, Equatable, Sendable { case invalidRoute, collision }

enum MultiPageStaticBuildPlanner {
    static func plan(document: CanonicalDocument) throws -> LocalStaticBuildPlan {
        let pages = document.pages.filter { $0.role != .componentDefinition }
        var files: [LocalStaticBuildPlan.File] = []
        var paths = Set<String>()
        for page in pages.sorted(by: { $0.route.rawValue < $1.route.rawValue }) {
            let output = try outputPath(for: page)
            guard paths.insert(output).inserted else { throw MultiPageStaticBuildError.collision }
            let body = try SafeHTMLEmitter.emit(
                InternalDocumentRenderTreeCompiler.compile(page: page, documentID: document.id, revision: document.revision)
            )
            files.append(.init(path: output, contents: body))
        }
        files.append(.init(path: "manifest.txt", contents: files.map(\.path).sorted().joined(separator: "\n")))
        return .init(revision: document.revision, files: files)
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
        return "<meta charset=\"utf-8\"><html lang=\"\(escape(metadata.language))\"><title>\(escape(metadata.title))</title>\(description)<meta name=\"robots\" content=\"\(metadata.index ? "index" : "noindex"), \(metadata.follow ? "follow" : "nofollow")\"><link rel=\"canonical\" href=\"\(route)\">"
    }
}

// SF-1208/SF-1211 v1: profile selection is an explicit noncanonical request.
enum LocalBuildProfile: String, Sendable { case development, production }
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
            case .production: contents = file.contents.replacingOccurrences(of: "\n", with: "")
        }
            return LocalStaticBuildPlan.File(path: file.path, contents: contents)
        }
        return (.init(revision: plan.revision, files: files), .init(revision: plan.revision, profile: profile, filePaths: files.map(\.path), deferredCapabilities: ["browser-runtime", "publishing"]))
    }
}

// SF-1203 v1 output is intentionally in-memory only. The fixed vocabulary and
// allowlist prevent authored content from becoming executable markup.
enum SafeHTMLEmissionError: Error, Equatable, Sendable { case unsupportedTag, invalidIdentity, invalidFormField }

enum SafeHTMLEmitter {
    static func emit(_ tree: InternalRenderTreeSnapshot) throws -> String {
        let ordered = tree.nodes.sorted { $0.paintOrder < $1.paintOrder }
        let formIDs = Set(ordered.filter { $0.semanticElement == "form" }.map(\.id))
        let fieldsByForm = Dictionary(grouping: ordered.compactMap { node -> InternalRenderTreeNode? in
            node.formField == nil ? nil : node
        }, by: { $0.formField!.formID })
        guard Set(fieldsByForm.keys).isSubset(of: formIDs) else { throw SafeHTMLEmissionError.invalidFormField }
        return try ordered.compactMap { node in
            if node.formField != nil { return nil }
            if node.semanticElement == "form" {
                let identifier = try validatedIdentifier(node)
                let fields = try (fieldsByForm[node.id] ?? []).map { try emitField($0, formIDs: formIDs) }.joined()
                return "<form data-siteforge-node=\"\(identifier)\" class=\"sf-node-\(identifier)\">\(fields)</form>"
            }
            return try emitNode(node, formIDs: formIDs)
        }.joined(separator: "\n")
    }

    private static func emitNode(_ node: InternalRenderTreeNode, formIDs: Set<NodeID>) throws -> String {
        let allowed = Set(["div", "section", "main", "header", "footer", "nav", "article", "aside", "p", "h1", "h2", "h3", "h4", "h5", "h6", "img", "button", "a", "form"])
        guard allowed.contains(node.semanticElement) else { throw SafeHTMLEmissionError.unsupportedTag }
        let identifier = try validatedIdentifier(node)
        if node.formField != nil {
            return try emitField(node, formIDs: formIDs)
        }
        let attributes = " data-siteforge-node=\"\(identifier)\" class=\"sf-node-\(identifier)\""
        return node.semanticElement == "img" ? "<img\(attributes)>" : "<\(node.semanticElement)\(attributes)></\(node.semanticElement)>"
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
    let frame: ViewportRect
    let paintOrder: Int
    let textContent: String?

    init(id: CanvasAccessibilityID, objectID: NodeID, label: String, frame: ViewportRect,
         paintOrder: Int, textContent: String? = nil) {
        self.id = id; self.objectID = objectID; self.label = label; self.frame = frame
        self.paintOrder = paintOrder; self.textContent = textContent
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
        let tiles = try buildTiles(objects: painted, viewport: viewport, cancellation: cancellation)
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
            tiles: tiles,
            accessibilityElements: accessibility,
            dirtyWorldRegions: dirty,
            invalidation: invalidation,
            deterministicDigest: digest(scene.objects)
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
            deterministicDigest: digest(scene.objects)
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
        guard scene.objects.count <= CanvasRendererPolicy.maximumObjects else {
            throw CanvasRendererError.objectLimitExceeded(scene.objects.count)
        }
        guard overlays.identity == scene.identity else { throw CanvasRendererError.staleResult }
        var ids = Set<NodeID>()
        var orders = Set<Int>()
        for (index, object) in scene.objects.enumerated() {
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
        guard !cancellation.isCancelled(scene.objects.count) else { throw CanvasRendererError.cancelled }
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
        return previous.objects == next.objects ? .compositorOnly : .dirtyRegions
    }

    private func dirtyRegions(
        previous: CanvasRenderSceneSnapshot?,
        next: CanvasRenderSceneSnapshot,
        invalidation: CanvasInvalidationKind
    ) -> [WorldRect] {
        guard invalidation == .dirtyRegions, let previous else {
            return invalidation == .compositorOnly ? [] : next.objects.map { rasterBounds(for: $0) }
        }
        let old = Dictionary(uniqueKeysWithValues: previous.objects.map { ($0.id, $0) })
        let new = Dictionary(uniqueKeysWithValues: next.objects.map { ($0.id, $0) })
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
