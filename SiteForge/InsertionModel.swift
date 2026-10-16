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
    case fluid
    case override(ResponsiveBreakpoint)

    var label: String {
        switch self {
        case .baseDesktop: "Inherited from Desktop"
        case .fluid: "Fluid responsive value"
        case .override(let value): "Authored for \(value.title)"
        }
    }
}

enum ResponsiveGeometryResolver {
    static let namespace = "responsive.geometry.v1"
    static func key(_ field: GeometryInspectorField, breakpoint: ResponsiveBreakpoint) -> String {
        "\(namespace).\(breakpoint.id.rawValue.uuidString.lowercased()).\(field.rawValue)"
    }
    static func value(for field: GeometryInspectorField, node: DocumentNode, breakpoint: ResponsiveBreakpoint,
                      viewportWidth: Double? = nil)
        -> (Double, PropertyOrigin, ResponsiveGeometrySource)? {
        if breakpoint != .desktop,
           let property = node.insertionProperty(key(field, breakpoint: breakpoint)),
           case .number(let value) = property.value, isValid(value, for: field) {
            return (value, property.origin, .override(breakpoint))
        }
        let fluidTarget: FluidValueTarget? = switch field {
        case .width: .width
        case .height: .height
        case .x, .y: nil
        }
        if let fluidTarget, let viewportWidth,
           let fluid = CanonicalFluidValueCodec.value(for: fluidTarget, node: node),
           let resolved = fluid.0.resolved(viewportWidth: viewportWidth) {
            return (resolved, fluid.1, .fluid)
        }
        guard let property = node.insertionProperty(field.propertyKey),
              case .number(let value) = property.value, isValid(value, for: field) else { return nil }
        return (value, property.origin, .baseDesktop)
    }
    static func geometry(for node: DocumentNode, breakpoint: ResponsiveBreakpoint,
                         viewportWidth: Double? = nil) -> InsertionGeometry? {
        guard let x = value(for: .x, node: node, breakpoint: breakpoint, viewportWidth: viewportWidth)?.0,
              let y = value(for: .y, node: node, breakpoint: breakpoint, viewportWidth: viewportWidth)?.0,
              let width = value(for: .width, node: node, breakpoint: breakpoint, viewportWidth: viewportWidth)?.0,
              let height = value(for: .height, node: node, breakpoint: breakpoint, viewportWidth: viewportWidth)?.0 else { return nil }
        return InsertionGeometry(origin: .init(x: x, y: y), size: .init(width: width, height: height))
    }
    static func frame(for node: DocumentNode, base: WorldRect, breakpoint: ResponsiveBreakpoint,
                      viewportWidth: Double? = nil) -> WorldRect {
        func resolved(_ field: GeometryInspectorField, fallback: Double) -> Double {
            value(for: field, node: node, breakpoint: breakpoint, viewportWidth: viewportWidth)?.0 ?? fallback
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
    static func value(for field: ContainerLayoutField, node: DocumentNode, breakpoint: ResponsiveBreakpoint,
                      viewportWidth: Double? = nil)
        -> (ContainerLayoutValue, PropertyOrigin, ResponsiveGeometrySource)? {
        if breakpoint != .desktop,
           let property = node.insertionProperty(key(field, breakpoint: breakpoint)),
           let value = parse(property.value, field: field) {
            return (value, property.origin, .override(breakpoint))
        }
        let fluidTarget: FluidValueTarget? = switch field {
        case .padding: .padding
        case .gap: .gap
        case .axis, .alignment, .columns: nil
        }
        if let fluidTarget, let viewportWidth,
           let fluid = CanonicalFluidValueCodec.value(for: fluidTarget, node: node),
           let resolved = fluid.0.resolved(viewportWidth: viewportWidth) {
            return (.number(resolved), fluid.1, .fluid)
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
    static let supportedKinds: Set<NodeKind> = [.frame, .text, .section, .stack, .grid, .image, .button, .link, .component]
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

struct ResponsiveStaticOutputReport: Equatable, Sendable {
    let appliedRuleCount: Int
    let breakpoints: [ResponsiveBreakpoint]
}

/// Immutable, static layout projection. This produces a small allowlisted CSS
/// subset from typed canonical geometry and breakpoint overrides only; it has
/// no authored CSS strings, browser execution, or document mutation path.
struct StaticLayoutOutputReport: Equatable, Sendable {
    let baseRuleCount: Int
    let responsiveRuleCount: Int
    let breakpoints: [ResponsiveBreakpoint]
}

enum StaticLayoutOutputEmitter {
    static func emit(nodes: [DocumentNode]) -> (css: String, report: StaticLayoutOutputReport) {
        let ordered = nodes.sorted { $0.id.description < $1.id.description }
        let base = ordered.compactMap(baseRule(for:))
        let responsive = responsiveRules(nodes: ordered)
        let fluid = StaticFluidValueOutputEmitter.emit(
            nodes: ordered, targets: [.width, .height, .padding, .gap])
        let css = ([base.joined(separator: "\n"), fluid, responsive.css].filter { !$0.isEmpty })
            .joined(separator: "\n")
        return (css, .init(baseRuleCount: base.count, responsiveRuleCount: responsive.report.appliedRuleCount,
                           breakpoints: responsive.report.breakpoints))
    }

    fileprivate static func responsiveRules(nodes: [DocumentNode]) -> (css: String, report: ResponsiveStaticOutputReport) {
        var output: [(ResponsiveBreakpoint, String)] = []
        for breakpoint in [ResponsiveBreakpoint.tablet, .mobile] {
            let rules = nodes.compactMap { responsiveRule(for: $0, breakpoint: breakpoint) }
            if !rules.isEmpty { output.append((breakpoint, rules.joined(separator: " "))) }
        }
        let css = output.map { breakpoint, rules in
            let query = breakpoint == .tablet
                ? "@media (min-width: 600px) and (max-width: 1023px)"
                : "@media (max-width: 599px)"
            return "\(query) { \(rules) }"
        }.joined(separator: "\n")
        return (css, .init(appliedRuleCount: output.count, breakpoints: output.map(\.0)))
    }

    private static func baseRule(for node: DocumentNode) -> String? {
        guard let geometry = ResponsiveGeometryResolver.geometry(for: node, breakpoint: .desktop),
              isValid(geometry) else { return nil }
        var declarations = geometryDeclarations(geometry)
        if ResponsiveVisibilityResolver.supports(node),
           !ResponsiveVisibilityResolver.isVisible(node, breakpoint: .desktop) {
            declarations.append("display: none;")
        } else {
            // Absolute static layout needs an explicit compatible box model;
            // this is not authored display/flex/grid state.
            declarations.append("display: block;")
        }
        return "\(CanonicalCSSRule.selector(for: node.id)) { \(declarations.joined(separator: " ")) }"
    }

    private static func responsiveRule(for node: DocumentNode, breakpoint: ResponsiveBreakpoint) -> String? {
        var declarations: [String] = []
        for field in GeometryInspectorField.allCases {
            let key = ResponsiveGeometryResolver.key(field, breakpoint: breakpoint)
            guard let property = node.insertionProperty(key), case .number(let value) = property.value,
                  isValid(value, for: field) else { continue }
            declarations.append("\(cssProperty(for: field)): \(number(value))px;")
        }
        if ResponsiveVisibilityResolver.supports(node),
           let property = node.insertionProperty(ResponsiveVisibilityResolver.key(breakpoint)),
           case .boolean(let visible) = property.value {
            declarations.append(visible ? "display: block;" : "display: none;")
        }
        guard !declarations.isEmpty else { return nil }
        return "\(CanonicalCSSRule.selector(for: node.id)) { \(declarations.joined(separator: " ")) }"
    }

    private static func geometryDeclarations(_ geometry: InsertionGeometry) -> [String] {
        [
            // Static dimensions are the canonical authored box, not a CSS
            // content box that expands later when bounded presentation rules
            // add borders or padding.
            "box-sizing: border-box;",
            "height: \(number(geometry.size.height))px;",
            "left: \(number(geometry.origin.x))px;",
            "position: absolute;",
            "top: \(number(geometry.origin.y))px;",
            "width: \(number(geometry.size.width))px;",
        ]
    }

    private static func cssProperty(for field: GeometryInspectorField) -> String {
        switch field { case .x: "left"; case .y: "top"; case .width: "width"; case .height: "height" }
    }

    private static func isValid(_ geometry: InsertionGeometry) -> Bool {
        isValid(geometry.origin.x, for: .x) && isValid(geometry.origin.y, for: .y)
            && isValid(geometry.size.width, for: .width) && isValid(geometry.size.height, for: .height)
    }

    private static func isValid(_ value: Double, for field: GeometryInspectorField) -> Bool {
        value.isFinite && abs(value) <= 1_000_000_000 && (!field.requiresPositiveValue || value >= 1)
    }

    private static func number(_ value: Double) -> String {
        let rounded = (value * 1_000).rounded() / 1_000
        var output = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        while output.contains(".") && output.last == "0" { output.removeLast() }
        if output.last == "." { output.append("0") }
        return output == "-0.0" ? "0.0" : output
    }
}

/// Closed SF-0604 projection. It emits only allowlisted properties and a
/// deterministic two-segment linear clamp matching the canvas resolver's
/// Mobile → Tablet → Desktop anchors. No authored CSS text crosses this edge.
enum StaticFluidValueOutputEmitter {
    static func emit(nodes: [DocumentNode], targets: Set<FluidValueTarget> = Set(FluidValueTarget.allCases)) -> String {
        nodes.sorted { $0.id.description < $1.id.description }.flatMap { node in
            FluidValueTarget.allCases.filter(targets.contains).compactMap { target -> String? in
                guard let fluid = CanonicalFluidValueCodec.value(for: target, node: node)?.0,
                      let property = cssProperty(target) else { return nil }
                let selector = CanonicalCSSRule.selector(for: node.id)
                let lower = segment(start: fluid.minimum, end: fluid.preferred,
                                    from: CanonicalFluidValue.lowerViewport,
                                    to: CanonicalFluidValue.preferredViewport)
                let upper = segment(start: fluid.preferred, end: fluid.maximum,
                                    from: CanonicalFluidValue.preferredViewport,
                                    to: CanonicalFluidValue.upperViewport)
                return "\(selector) { \(property): \(lower); } @media (min-width: 768px) { \(selector) { \(property): \(upper); } }"
            }
        }.joined(separator: "\n")
    }

    private static func cssProperty(_ target: FluidValueTarget) -> String? {
        switch target {
        case .width: "width"
        case .height: "height"
        case .fontSize: "font-size"
        case .lineHeight: "line-height"
        case .padding: "padding"
        case .gap: "gap"
        }
    }

    private static func segment(start: Double, end: Double, from lower: Double, to upper: Double) -> String {
        guard end != start else { return "\(number(start))px" }
        let slope = (end - start) / (upper - lower)
        let vw = slope * 100
        let intercept = start - slope * lower
        let offset = intercept < 0
            ? "- \(number(abs(intercept)))px"
            : "+ \(number(intercept))px"
        return "clamp(\(number(start))px, calc(\(number(vw))vw \(offset)), \(number(end))px)"
    }

    private static func number(_ value: Double) -> String {
        let rounded = (value * 1_000).rounded() / 1_000
        var output = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        while output.contains(".") && output.last == "0" { output.removeLast() }
        if output.last == "." { output.removeLast() }
        return output == "-0" ? "0" : output
    }
}

/// Fixed-breakpoint static CSS only; all values originate in typed canonical
/// override namespaces, never authored CSS/media strings.
enum ResponsiveStaticCSSEmitter {
    static func emit(nodes: [DocumentNode]) -> (css: String, report: ResponsiveStaticOutputReport) {
        StaticLayoutOutputEmitter.responsiveRules(nodes: nodes.sorted { $0.id.description < $1.id.description })
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
    case button
    case link
    case form

    var nodeKind: NodeKind {
        switch self {
        case .frame: .frame
        case .text: .text
        case .section: .section
        case .stack: .stack
        case .grid: .grid
        case .image: .image
        case .button: .button
        case .link: .link
        case .form: .form
        }
    }

    var requirementID: String {
        switch self {
        case .frame, .text: "SF-0405-008"
        case .section: "SF-0405-001"
        case .stack: "SF-0502-001"
        case .grid: "SF-0503-001"
        case .image: "SF-0802-002"
        case .button, .link: "SF-1102-002"
        case .form: "SF-1006-001"
        }
    }
}

/// Named catalogue templates retain the established Frame/Section node kinds
/// and insertion transaction. They are not a second authored element schema.
enum AuthoringElementTemplate: String, Sendable {
    case heading, divider, header, navigation, footer
    case input, emailInput, textArea, checkbox, selectField, submit

    var displayName: String {
        switch self {
        case .emailInput: "Email"
        case .textArea: "Text Area"
        case .selectField: "Select"
        default: rawValue.capitalized
        }
    }

    var formFieldKind: FormFieldKind? {
        switch self {
        case .input: .text
        case .emailInput: .email
        case .textArea: .textarea
        case .checkbox: .checkbox
        case .selectField: .select
        case .submit: .submit
        case .heading, .divider, .header, .navigation, .footer: nil
        }
    }

    var insertionKind: InsertionKind {
        switch self {
        case .divider: .frame
        case .heading, .input, .emailInput, .textArea, .checkbox, .selectField, .submit: .text
        case .header, .navigation, .footer: .section
        }
    }
    var size: WorldSize {
        switch self {
        case .heading: WorldSize(width: 360, height: 48)
        case .divider: WorldSize(width: 240, height: 1)
        case .header: WorldSize(width: 960, height: 120)
        case .navigation: WorldSize(width: 960, height: 80)
        case .footer: WorldSize(width: 960, height: 200)
        case .input: WorldSize(width: 240, height: 36)
        case .emailInput, .selectField: WorldSize(width: 240, height: 36)
        case .textArea: WorldSize(width: 240, height: 100)
        case .checkbox: WorldSize(width: 240, height: 28)
        case .submit: WorldSize(width: 160, height: 44)
        }
    }
    var semanticElement: SemanticHTMLElement? {
        switch self {
        case .divider, .input, .emailInput, .textArea, .checkbox, .selectField, .submit: nil
        case .heading: .h2
        case .header: .header
        case .navigation: .nav
        case .footer: .footer
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
        case .button: WorldSize(width: 160, height: 44)
        case .link: WorldSize(width: 120, height: 24)
        case .form: WorldSize(width: 320, height: 180)
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

struct ControlInsertionCommand: Equatable, Sendable {
    let kind: InsertionKind
    let identity: InsertionOperationIdentity
    let nodeID: NodeID
    let parentID: NodeID
    let index: Int
    let geometry: InsertionGeometry
    let provenance: InsertionProvenance
}

enum AuthoringInsertionCommand: Equatable, Sendable {
    case frame(FrameInsertionCommand)
    case text(TextInsertionCommand)
    case container(ContainerInsertionCommand)
    case image(ImageInsertionCommand)
    case control(ControlInsertionCommand)

    var kind: InsertionKind {
        switch self {
        case .frame: .frame
        case .text: .text
        case .container(let value): value.kind
        case .image: .image
        case .control(let value): value.kind
        }
    }

    var identity: InsertionOperationIdentity {
        switch self {
        case .frame(let value): value.identity
        case .text(let value): value.identity
        case .container(let value): value.identity
        case .image(let value): value.identity
        case .control(let value): value.identity
        }
    }

    var nodeID: NodeID {
        switch self {
        case .frame(let value): value.nodeID
        case .text(let value): value.nodeID
        case .container(let value): value.nodeID
        case .image(let value): value.nodeID
        case .control(let value): value.nodeID
        }
    }

    var parentID: NodeID {
        switch self {
        case .frame(let value): value.parentID
        case .text(let value): value.parentID
        case .container(let value): value.parentID
        case .image(let value): value.parentID
        case .control(let value): value.parentID
        }
    }

    var index: Int {
        switch self {
        case .frame(let value): value.index
        case .text(let value): value.index
        case .container(let value): value.index
        case .image(let value): value.index
        case .control(let value): value.index
        }
    }

    var geometry: InsertionGeometry {
        switch self {
        case .frame(let value): value.geometry
        case .text(let value): value.geometry
        case .container(let value): value.geometry
        case .image(let value): value.geometry
        case .control(let value): value.geometry
        }
    }

    var provenance: InsertionProvenance {
        switch self {
        case .frame(let value): value.provenance
        case .text(let value): value.provenance
        case .container(let value): value.provenance
        case .image(let value): value.provenance
        case .control(let value): value.provenance
        }
    }

    var text: String? {
        if case .control(let value) = self { return value.kind.rawValue.capitalized }
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
    let breakpoint: ResponsiveBreakpoint
    let viewportWidth: Double?

    init(
        activePageID: PageID,
        activeRoute: PageRoute,
        operationGeneration: UInt64,
        availableNodeIDs: Set<NodeID>? = nil,
        isLifecycleAvailable: Bool = true,
        lifecycleDisabledReason: String? = nil,
        breakpoint: ResponsiveBreakpoint = .desktop,
        viewportWidth: Double? = nil
    ) {
        self.activePageID = activePageID
        self.activeRoute = activeRoute
        self.operationGeneration = operationGeneration
        self.availableNodeIDs = availableNodeIDs
        self.isLifecycleAvailable = isLifecycleAvailable
        self.lifecycleDisabledReason = lifecycleDisabledReason
        self.breakpoint = breakpoint
        self.viewportWidth = viewportWidth
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
    case formParentRequired
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
        case .incompatibleParent: "Choose a supported containing area. Header/Footer are unique page anchors; connected page structure is not component content."
        case .formParentRequired: "Select an unlocked Form on the active page to insert a field."
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
        context: InsertionValidationContext,
        template: AuthoringElementTemplate? = nil
    ) -> InsertionAvailability {
        do {
            _ = try prepare(command, in: document, context: context, template: template)
            return .enabled
        } catch {
            return .disabled(error.localizedDescription)
        }
    }

    func prepare(
        _ command: AuthoringInsertionCommand,
        in document: CanonicalDocument,
        context: InsertionValidationContext,
        cancellation: InsertionCancellation = .never,
        template: AuthoringElementTemplate? = nil
    ) throws -> PreparedInsertion {
        guard !cancellation.isCancelled() else { throw InsertionError.cancelled }
        if let template, template.insertionKind != command.kind { throw InsertionError.incompatibleParent }
        if case .control(let control) = command, ![InsertionKind.button, .link].contains(control.kind) {
            throw InsertionError.incompatibleParent
        }
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
        guard page.role != .componentDefinition || (template != .header && template != .footer) else {
            throw InsertionError.incompatibleParent
        }
        guard !document.pages.flatMap(\.nodes).contains(where: { $0.id == command.nodeID }) else {
            throw InsertionError.duplicateNode
        }
        guard document.pages.reduce(0, { $0 + $1.nodes.count }) < InsertionPolicy.maximumNodeCount else {
            throw InsertionError.nodeLimitExceeded
        }
        let flowRole: PageFlowRole? = page.role != .componentDefinition && command.kind == .section && template != .navigation
            ? (template == .header ? .header : template == .footer ? .footer : .body) : nil
        let requestedParent = page.nodes.first { $0.id == command.parentID }
        let anchored = flowRole == .header || flowRole == .footer
        let redirect = requestedParent.flatMap(CanonicalPageFlow.role).map { $0 != .body } ?? false
        let contentParent = requestedParent.flatMap { CanonicalPageChrome.reference(CanonicalPageChrome.contentKey, on: $0) }
        let parentID = anchored || (flowRole == .body && redirect) ? (page.rootNodeIDs.first ?? command.parentID)
            : contentParent ?? command.parentID
        guard let parent = page.nodes.first(where: { $0.id == parentID }) else {
            if document.pages.flatMap(\.nodes).contains(where: { $0.id == command.parentID }) {
                throw InsertionError.crossPageParent
            }
            throw InsertionError.missingParent
        }
        guard parent.kind.acceptsAuthoredChildren else { throw InsertionError.incompatibleParent }
        if template?.formFieldKind != nil, parent.kind != .form {
            throw InsertionError.formParentRequired
        }
        guard !parent.insertionBooleanProperty("locked") else { throw InsertionError.lockedParent }
        guard !parent.insertionBooleanProperty("hidden") else { throw InsertionError.hiddenParent }
        if let availableNodeIDs = context.availableNodeIDs,
           !availableNodeIDs.contains(parent.id) {
            throw InsertionError.unavailableParent
        }
        guard flowRole != nil || parentID != command.parentID || (0...parent.childIDs.count).contains(command.index) else {
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
        var node = makeNode(for: command)
        node.parent = .node(parentID)
        if let flowRole {
            node.parent = .node(parentID)
            node.properties.append(property(node.id, CanonicalPageFlow.roleKey, .string(flowRole.rawValue), .defaulted))
            for key in ["layout.x", "layout.y", "layout.width"] {
                if let index = node.properties.firstIndex(where: { $0.key.rawValue == key }) {
                    node.properties[index].value = .number(key == "layout.width" ? 960 : 0)
                    node.properties[index].origin = .defaulted
                }
            }
            if let template, let index = node.properties.firstIndex(where: { $0.key.rawValue == "layout.height" }) {
                node.properties[index].value = .number(template.size.height)
            }
        }
        if let template {
            node.name = template.displayName
            if let semantic = template.semanticElement {
                node.properties.append(property(node.id, CanonicalSemanticElement.key,
                    .string(semantic.rawValue), .authored))
            }
            if template == .divider {
                // A one-point authored surface has no border expansion; the
                // selection outline remains editor-only and uses its frame.
                node.properties.removeAll { $0.key.rawValue == "style.border" }
                node.properties.append(property(node.id, "style.border", .string("none"), .defaulted))
            }
            if template == .heading {
                // Heading is a semantic Text template, not a parallel node
                // kind. Its defaults remain editable through the established
                // Content, Typography, and semantic-element controls.
                func replace(_ key: String, _ value: PropertyValue) {
                    node.properties.removeAll { $0.key.rawValue == key }
                    node.properties.append(property(node.id, key, value, .defaulted))
                }
                replace("content.text", .string("Heading"))
                replace(CanonicalTypography.namespace + "weight", .string(CanonicalFontWeight.bold.rawValue))
                replace(CanonicalTypography.namespace + "size", .number(32))
                replace(CanonicalTypography.namespace + "lineHeight", .number(38))
            }
            if let fieldKind = template.formFieldKind {
                // Form fields are existing Text nodes. A stable name derived
                // from NodeID avoids collision without borrowing local input.
                node.properties.removeAll { $0.key.rawValue == "content.text" }
                node.properties.append(property(node.id, "content.text", .string(template.displayName), .defaulted))
                node.properties += [
                    property(node.id, CanonicalFormField.kindKey, .string(fieldKind.rawValue), .defaulted),
                    property(node.id, CanonicalFormField.labelKey, .string(template.displayName), .defaulted),
                    property(node.id, CanonicalFormField.nameKey,
                             .string("field" + node.id.rawValue.uuidString.replacingOccurrences(of: "-", with: "").lowercased()), .defaulted),
                    property(node.id, CanonicalFormField.requiredKey, .boolean(false), .defaulted),
                ]
                if fieldKind == .select {
                    let options = (1...2).map { index in
                        CanonicalFormSelectOption(
                            id: FormOptionID(Self.derivedUUID(namespace: node.id.rawValue,
                                label: "form.option.\(index)")),
                            label: "Option \(index)", value: "option-\(index)")
                    }
                    node.properties.append(property(node.id, CanonicalFormField.optionsKey,
                        .string(try CanonicalFormSelectOptions.encode(options)), .defaulted))
                }
            }
        }
        let index = flowRole.map { CanonicalPageFlow.insertionIndex(role: $0, parent: parent, page: page,
            pointerY: command.provenance == .pointer ? command.geometry.origin.y : nil,
            breakpoint: context.breakpoint, width: context.viewportWidth) }
            ?? (parentID == command.parentID ? command.index : parent.childIDs.count)
        var chrome: CanonicalPageChrome.Contents?
        if anchored {
            guard document.websitePages.filter({ $0.role != .notFound }).count <= CanonicalPageFlow.maximumLinks else {
                throw InsertionError.nodeLimitExceeded
            }
            let contents = CanonicalPageChrome.defaults(ownerID: node.id, document: document)
            guard document.pages.reduce(0, { $0 + $1.nodes.count }) + 1 + contents.nodes.count <= InsertionPolicy.maximumNodeCount else {
                throw InsertionError.nodeLimitExceeded
            }
            for (key, value) in contents.references { node.properties.append(property(node.id, key, value, .defaulted)) }
            node.properties.append(property(node.id, CanonicalPageFlow.hamburgerKey, .boolean(true), .defaulted))
            node.childIDs = [contents.content.id]
            chrome = contents
        }
        var insertionNode = node
        if chrome != nil { insertionNode.childIDs = [] }
        var commands: [DocumentCommand] = [.insertNode(.init(pageID: page.id, node: insertionNode, index: index))]
        if let chrome {
            let complete = [node] + chrome.nodes
            for child in chrome.nodes {
                guard case .node(let parentID) = child.parent,
                      let parent = complete.first(where: { $0.id == parentID }),
                      let childIndex = parent.childIDs.firstIndex(of: child.id) else { throw InsertionError.incompatibleParent }
                var inserted = child; inserted.childIDs = []
                commands.append(.insertNode(.init(pageID: page.id, node: inserted, index: childIndex)))
            }
        }
        let documentCommand = commands.count == 1 ? commands[0] : .batch(commands)
        if flowRole != nil {
            var candidate = document
            guard let pageIndex = candidate.pages.firstIndex(where: { $0.id == page.id }),
                  let parentIndex = candidate.pages[pageIndex].nodes.firstIndex(where: { $0.id == parent.id }),
                  (0...parent.childIDs.count).contains(index) else { throw InsertionError.invalidIndex }
            candidate.pages[pageIndex].nodes[parentIndex].childIDs.insert(node.id, at: index)
            candidate.pages[pageIndex].nodes.append(node)
            if let chrome { candidate.pages[pageIndex].nodes += chrome.nodes }
            do { try candidate.validate() } catch { throw InsertionError.incompatibleParent }
        }
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
            property(command.nodeID, "style.fill", .string([InsertionKind.text, .link].contains(command.kind) ? "text-placeholder" : "surface"), .defaulted),
            property(command.nodeID, "style.border", .string([InsertionKind.text, .link].contains(command.kind) ? "none" : "subtle"), .defaulted),
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
        case .button, .link:
            properties += [property(command.nodeID, CanonicalLinkTarget.namespace + "kind", .string("none"), .defaulted),
                           property(command.nodeID, CanonicalLinkTarget.namespace + "context", .string("same"), .defaulted)]
        case .frame, .text, .form: break
        }
        if let text = command.text {
            properties.append(property(command.nodeID, command.kind.nodeKind.isLinkControl ? CanonicalLinkTarget.labelKey : "content.text", .string(text), .defaulted))
            let typography = CanonicalTypography.defaultValue
            properties += [
                property(command.nodeID, CanonicalTypography.namespace + "family", .string(typography.family), .defaulted),
                property(command.nodeID, CanonicalTypography.namespace + "weight", .string(typography.weight.rawValue), .defaulted),
                property(command.nodeID, CanonicalTypography.namespace + "size", .number(typography.size), .defaulted),
                property(command.nodeID, CanonicalTypography.namespace + "lineHeight", .number(typography.lineHeight), .defaulted),
                property(command.nodeID, CanonicalTypography.namespace + "tracking", .number(typography.tracking), .defaulted),
                property(command.nodeID, CanonicalTypography.namespace + "alignment", .string(command.kind == .button ? "center" : typography.alignment.rawValue), .defaulted),
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
/// Read-only component expansion. Canonical pages contain only instance roots;
/// expanded children are revision-scoped rendering data, never a write target.
enum ComponentResolutionError: Error, Equatable {
    case objectLimitExceeded(Int)
    case duplicateObject(NodeID)
}

enum ComponentGraphResolver {
    /// Placement is scene input, not a responsive rewrite of the definition.
    /// Bound a new instance to the visible portion of its canonical parent.
    static func insertionGeometry(source: InsertionGeometry, parentFrame: WorldRect?,
                                  artboard: WorldRect) -> InsertionGeometry? {
        let parent = parentFrame ?? artboard
        let left = max(parent.minX, artboard.minX), top = max(parent.minY, artboard.minY)
        let right = min(parent.maxX, artboard.maxX), bottom = min(parent.maxY, artboard.maxY)
        guard [left, top, right, bottom, source.size.width, source.size.height].allSatisfy(\.isFinite),
              right - left >= 1, bottom - top >= 1,
              source.size.width >= 1, source.size.height >= 1 else { return nil }
        let width = min(source.size.width, right - left)
        let height = min(source.size.height, bottom - top)
        return .init(origin: .init(x: left + (right - left - width) / 2,
                                  y: top + (bottom - top - height) / 2),
                     size: .init(width: width, height: height))
    }
    /// Detachment materializes every supported breakpoint, not just the
    /// current viewport. Instance-owned geometry keeps its original property
    /// identities; derived child coordinates become ordinary overrides.
    static func detachedNodes(_ instance: DocumentNode, definition: DocumentPage,
                              page: DocumentPage) -> [DocumentNode]? {
        guard CanonicalComponentText.unresolvedOverrides(on: instance, definition: definition).isEmpty,
              CanonicalComponentVisibility.unresolvedOverrides(on: instance, definition: definition).isEmpty,
              Set(CanonicalComponentChoice.overrides(on: instance).keys).isSubset(of:
                Set(CanonicalComponentChoice.properties(in: definition).map(\.id))),
              Set(CanonicalComponentMedia.overrides(on: instance).keys).isSubset(of:
                Set(CanonicalComponentMedia.properties(in: definition).map(\.id))),
              Set(CanonicalComponentAction.overrides(on: instance).keys).isSubset(of:
                Set(CanonicalComponentAction.properties(in: definition).map(\.id))),
              let geometry = page.resolvedStructuralGeometry(breakpoint: .desktop)[instance.id],
              var nodes = expand(instance, definition: definition, pageID: page.id,
                                 geometry: geometry, breakpoint: .desktop) else { return nil }
        for breakpoint in ResponsiveBreakpoint.allCases where breakpoint != .desktop {
            guard let placement = page.resolvedStructuralGeometry(breakpoint: breakpoint)[instance.id],
                  let resolved = expand(instance, definition: definition, pageID: page.id,
                                        geometry: placement, breakpoint: breakpoint) else { return nil }
            for index in nodes.indices where nodes[index].id != instance.id {
                for field in GeometryInspectorField.allCases {
                    guard let value = resolved[index].insertionProperty(field.propertyKey),
                          value.value != nodes[index].insertionProperty(field.propertyKey)?.value else { continue }
                    let key = ResponsiveGeometryResolver.key(field, breakpoint: breakpoint)
                    nodes[index].properties.append(NodeProperty(
                        id: PropertyID(DocumentPage.deterministicUUID(namespace: nodes[index].id.rawValue, label: key)),
                        key: .init(rawValue: key), value: value.value, origin: value.origin))
                }
            }
        }
        if let index = nodes.firstIndex(where: { $0.id == instance.id }) {
            let placement = instance.properties.filter {
                GeometryInspectorField.allCases.map(\.propertyKey).contains($0.key.rawValue)
                    || $0.key.rawValue.hasPrefix(ResponsiveGeometryResolver.namespace + ".")
            }
            let keys = Set(placement.map(\.key))
            nodes[index].properties.removeAll { keys.contains($0.key) }
            nodes[index].properties += placement
        }
        return nodes
    }

    /// Apply the renderer's existing object budget before allocating any
    /// instance expansion. Cancellation is checked between bounded graphs.
    static func resolvedPage(_ page: DocumentPage, in document: CanonicalDocument,
                            breakpoint: ResponsiveBreakpoint,
                            maximumNodes: Int = ResolvedGraphPolicy.maximumNodes,
                            checkpoint: () throws -> Void = {}) throws -> DocumentPage {
        let definitions = Dictionary(uniqueKeysWithValues: document.componentDefinitions.map { ($0.id, $0) })
        var count = 0
        for node in page.nodes {
            try checkpoint()
            let size = CanonicalComponentReference.definitionID(for: node)
                .flatMap { definitions[$0]?.nodes.count } ?? 1
            guard size <= maximumNodes - count else {
                throw ComponentResolutionError.objectLimitExceeded(maximumNodes + 1)
            }
            count += size
        }
        let placement = page.resolvedStructuralGeometry(breakpoint: breakpoint)
        var output = page
        output.nodes = []
        output.nodes.reserveCapacity(count)
        var occupied = Set(page.nodes.map(\.id))
        for instance in page.nodes {
            try checkpoint()
            guard let definitionID = CanonicalComponentReference.definitionID(for: instance),
                  let definition = definitions[definitionID], let geometry = placement[instance.id],
                  let expanded = expand(instance, definition: definition, pageID: page.id,
                                        geometry: geometry, breakpoint: breakpoint) else {
                output.nodes.append(instance)
                continue
            }
            for node in expanded where node.id != instance.id {
                try checkpoint()
                guard occupied.insert(node.id).inserted else { throw ComponentResolutionError.duplicateObject(node.id) }
            }
            output.nodes += expanded
        }
        return CanonicalPageChrome.resolvedLabels(in: output, document: document)
    }

    static func expand(_ instance: DocumentNode, definition: DocumentPage, pageID: PageID,
                       geometry: InsertionGeometry, breakpoint: ResponsiveBreakpoint) -> [DocumentNode]? {
        guard definition.role == .componentDefinition,
              let rootID = definition.rootNodeIDs.first,
              !definition.nodes.contains(where: { $0.kind == .component }) else { return nil }
        let frames = definition.resolvedStructuralGeometry(breakpoint: breakpoint)
        let textOverrides = CanonicalComponentText.overrides(on: instance)
        let visibilityOverrides = CanonicalComponentVisibility.overrides(on: instance)
        let choiceOverrides = CanonicalComponentChoice.overrides(on: instance)
        let mediaOverrides = CanonicalComponentMedia.overrides(on: instance)
        let actionOverrides = CanonicalComponentAction.overrides(on: instance)
        guard let rootGeometry = frames[rootID] else { return nil }
        let ids = Dictionary(uniqueKeysWithValues: definition.nodes.map { node in
            (node.id, node.id == rootID ? instance.id : NodeID(DocumentPage.deterministicUUID(
                namespace: instance.id.rawValue, label: "component-child:" + node.id.description)))
        })
        return definition.nodes.map { node in
            let id = ids[node.id]!
            let isRoot = node.id == rootID
            let visibilityBinding = CanonicalComponentVisibility.property(on: node)
            var properties = node.properties.filter {
                !$0.key.rawValue.hasPrefix("responsive.geometry.v1.")
                    && !$0.key.rawValue.hasPrefix(CanonicalComponentText.namespace)
                    && !$0.key.rawValue.hasPrefix(CanonicalComponentVisibility.namespace)
                    && !$0.key.rawValue.hasPrefix(CanonicalComponentChoice.namespace)
                    && !$0.key.rawValue.hasPrefix(CanonicalComponentMedia.namespace)
                    && !$0.key.rawValue.hasPrefix(CanonicalComponentAction.namespace)
                    && !$0.key.rawValue.hasPrefix(CanonicalComponentSlot.namespace)
                    && !$0.key.rawValue.hasPrefix(CanonicalComponentOrganization.namespace)
                    && (visibilityBinding == nil || !$0.key.rawValue.hasPrefix(ResponsiveVisibilityResolver.namespace + "."))
            }.map { property in
                NodeProperty(id: PropertyID(DocumentPage.deterministicUUID(namespace: id.rawValue,
                    label: "component-property:" + property.id.description)), key: property.key,
                    value: property.value, origin: property.origin)
            }
            // One resolution for raster, accessibility and detachment. An
            // authored empty string is a value, never an inheritance sentinel.
            if let binding = CanonicalComponentText.property(on: node),
               let text = textOverrides[binding.id],
               let index = properties.firstIndex(where: { $0.key.rawValue == "content.text" }) {
                properties[index].value = .string(text)
                properties[index].origin = .authored
            }
            if let binding = visibilityBinding {
                let visible = CanonicalComponentVisibility.resolvedVisible(for: node,
                    overrides: visibilityOverrides)
                let old = properties.first { $0.key.rawValue == "hidden" }
                let effective = NodeProperty(id: old?.id ?? PropertyID(DocumentPage.deterministicUUID(
                    namespace: id.rawValue, label: "component-visibility:" + binding.id.description)),
                    key: .init(rawValue: "hidden"), value: .boolean(!visible),
                    origin: visibilityOverrides[binding.id] == nil ? .defaulted : .authored)
                if let index = properties.firstIndex(where: { $0.key.rawValue == "hidden" }) {
                    properties[index] = effective
                } else { properties.append(effective) }
            }
            if let binding = CanonicalComponentChoice.property(on: node),
               let value = choiceOverrides[binding.id] {
                let key = CanonicalImageStyle.namespace + "fit"
                if let index = properties.firstIndex(where: { $0.key.rawValue == key }) {
                    properties[index].value = .string(value.rawValue)
                    properties[index].origin = .authored
                }
            }
            if let binding = CanonicalComponentMedia.property(on: node),
               let value = mediaOverrides[binding.id] {
                let key = CanonicalImageStyle.namespace + "assetID"
                if let index = properties.firstIndex(where: { $0.key.rawValue == key }) {
                    properties[index].value = .string(value.description)
                    properties[index].origin = .authored
                }
            }
            if let binding = CanonicalComponentAction.property(on: node),
               let target = actionOverrides[binding.id] {
                let owned = Set(["kind", "pageID", "nodeID", "url"].map { CanonicalLinkTarget.namespace + $0 })
                properties.removeAll { owned.contains($0.key.rawValue) }
                properties += target.properties.map { key, value in
                    NodeProperty(id: PropertyID(DocumentPage.deterministicUUID(namespace: id.rawValue,
                        label: "component-action:" + binding.id.description + ":" + key)),
                        key: .init(rawValue: key), value: value, origin: .authored)
                }
            }
            if let frame = frames[node.id] {
                let values: [String: Double] = [
                    "layout.x": isRoot ? geometry.origin.x : geometry.origin.x + frame.origin.x - rootGeometry.origin.x,
                    "layout.y": isRoot ? geometry.origin.y : geometry.origin.y + frame.origin.y - rootGeometry.origin.y,
                    "layout.width": isRoot ? geometry.size.width : frame.size.width,
                    "layout.height": isRoot ? geometry.size.height : frame.size.height,
                ]
                for index in properties.indices {
                    if let value = values[properties[index].key.rawValue] { properties[index].value = .number(value) }
                }
            }
            if isRoot {
                let visibility = instance.properties.filter {
                    $0.key.rawValue.hasPrefix("responsive.visibility.v1.") || ["hidden", "locked"].contains($0.key.rawValue)
                }
                let keys = Set(visibility.map(\.key))
                properties.removeAll { keys.contains($0.key) }
                properties += visibility
            }
            // Internal definition links resolve to this instance's graph;
            // outbound stable references remain untouched.
            for index in properties.indices {
                if properties[index].key.rawValue == CanonicalLinkTarget.namespace + "pageID",
                   properties[index].value == .string(definition.id.description) {
                    properties[index].value = .string(pageID.description)
                }
                if properties[index].key.rawValue == CanonicalLinkTarget.namespace + "nodeID",
                   case .string(let old) = properties[index].value,
                   let oldID = NodeID(uuidString: old), let mapped = ids[oldID] {
                    properties[index].value = .string(mapped.description)
                }
            }
            let parent: NodeParent = if isRoot { instance.parent }
                else if case .node(let parentID) = node.parent { .node(ids[parentID]!) }
                else { .page(pageID) }
            return DocumentNode(id: id, kind: node.kind, name: isRoot ? instance.name : node.name,
                parent: parent, childIDs: node.childIDs.compactMap { ids[$0] }, properties: properties)
        }
    }
}

enum ConnectedPageOutput {
    static let menuCSS = """
    .sf-connected-page { position:relative;width:100%;min-height:900px;overflow:hidden; }
    body.sf-connected-body { margin:0; }
    .sf-page-navigation { position:absolute;box-sizing:border-box;font:14px system-ui; }
    .sf-nav-inline { display:flex;align-items:center;min-width:0; }
    .sf-nav-inline a { flex:none;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis; }
    .sf-nav-menu { display:none;position:relative;width:max-content;max-width:100%; }
    .sf-nav-menu summary { list-style:none;cursor:pointer; }
    .sf-nav-menu summary::-webkit-details-marker { display:none; }
    @media (width < 600px) { .sf-nav-responsive { display:none; } .sf-nav-menu { display:block; } .sf-nav-menu[open] nav { display:flex;position:absolute;z-index:100;min-width:160px;max-width:min(320px,80vw);max-height:50vh;overflow:auto;flex-direction:column;gap:8px;padding:12px;background:Canvas;color:CanvasText;box-shadow:0 4px 16px #0003; } footer .sf-nav-menu[open] nav { bottom:100%; } }
    """
    static let menuScript = """
    (function(){
    const selector='details[data-siteforge-navigation]';
    function close(menu,restore){menu.open=false;const summary=menu.querySelector('summary');if(summary){summary.setAttribute('aria-expanded','false');if(restore)summary.focus();}}
    document.addEventListener('toggle',function(event){const menu=event.target;if(!(menu instanceof HTMLDetailsElement)||!menu.matches(selector))return;const summary=menu.querySelector('summary');if(summary)summary.setAttribute('aria-expanded',String(menu.open));if(menu.open)document.querySelectorAll(selector+'[open]').forEach(function(other){if(other!==menu)close(other,false);});},true);
    document.addEventListener('keydown',function(event){if(event.key!=='Escape')return;const menu=(event.target instanceof Element?event.target.closest(selector):null)||document.querySelector(selector+'[open]');if(menu&&menu.open){close(menu,true);event.preventDefault();}});
    document.addEventListener('click',function(event){const target=event.target;if(!(target instanceof Element))return;document.querySelectorAll(selector+'[open]').forEach(function(menu){if(!menu.contains(target)||target.closest('[data-siteforge-nav-link]'))close(menu,false);});});
    document.addEventListener('focusin',function(event){document.querySelectorAll(selector+'[open]').forEach(function(menu){if(!menu.contains(event.target))close(menu,false);});});
    window.matchMedia('(width < 600px)').addEventListener('change',function(event){if(event.matches)return;document.querySelectorAll(selector+'[open]').forEach(function(menu){const focused=menu.contains(document.activeElement);close(menu,false);if(focused){const owner=menu.closest('.sf-page-navigation');const first=owner&&Array.from(owner.querySelectorAll('.sf-nav-inline a[href]')).find(function(link){return link.getClientRects().length>0;});if(first)first.focus();else document.body.focus();}});});
    }());
    """
    static func css(pages: [DocumentPage]) -> String {
        var rules: [String] = []
        for page in pages where page.nodes.contains(where: { CanonicalPageFlow.role($0) != nil }) {
            let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
            for breakpoint in ResponsiveBreakpoint.allCases {
                let width = CanonicalPageFlow.pageWidth(breakpoint, nil)
                let snapshot = ConnectedPageLayoutSnapshot(page: page, breakpoint: breakpoint, width: width)
                var current = [".sf-page-\(page.id) { height:\(snapshot.contentHeight)px; }"]
                for node in page.canonicalDepthFirstNodes() {
                    let selector = CanonicalCSSRule.selector(for: node.id)
                    if CanonicalPageFlow.isNavigationLink(node) {
                        current.append(".sf-nav-link-\(node.id) { display:\(snapshot.visibleIDs.contains(node.id) ? "block" : "none"); }")
                        continue
                    }
                    guard snapshot.visibleIDs.contains(node.id) else {
                        current.append("\(selector) { display:none; }")
                        continue
                    }
                    let frame = snapshot.frames[node.id]
                    if page.rootNodeIDs.contains(node.id), frame == nil {
                        current.append("\(selector) { display:flow-root;position:relative;left:0;top:0;width:100%;height:\(snapshot.contentHeight)px;box-sizing:border-box;padding:0;margin:0; }")
                        continue
                    }
                    guard let frame else {
                        // Retain semantic identity without creating layout
                        // space for a node the native renderer cannot paint.
                        current.append("\(selector) { display:none; }")
                        continue
                    }
                    let parentID: NodeID? = { if case .node(let id) = node.parent { id } else { nil } }()
                    let parentFrame = parentID.flatMap { snapshot.frames[$0] }
                    let parent = parentID.flatMap { byID[$0] }
                    let policy = parentID.flatMap { snapshot.policies[$0] }
                    let localX = frame.origin.x - (parentFrame?.origin.x ?? 0)
                    let localY = frame.origin.y - (parentFrame?.origin.y ?? 0)
                    var declarations = ["display:block", "position:absolute", "box-sizing:border-box", "padding:0", "margin:0",
                        "left:\(localX)px", "top:\(localY)px", "width:\(frame.size.width)px", "height:\(frame.size.height)px"]
                    if let parent, let policy,
                       parent.kind == .grid || parent.kind == .stack || parent.kind == .section || parent.kind == .form
                        || (parent.kind == .frame && !policy.naturalFlow && DesignBoxStyleCommandRegistry.resolvedStyle(for: parent)?.padding != nil) {
                        let index = snapshot.childIndices[node.id] ?? 0
                        if parent.kind == .grid {
                            let cell = "calc(max(1px,calc(100% - \(2 * policy.padding + Double(policy.columns - 1) * policy.gap)px)) / \(policy.columns))"
                            declarations += ["width:\(cell)", "left:calc(\(policy.padding)px + \(index % policy.columns) * (\(cell) + \(policy.gap)px))"]
                        } else if policy.axis == .vertical {
                            let basis = ResponsiveGeometryResolver.geometry(for: node, breakpoint: breakpoint, viewportWidth: width)?.size.width ?? frame.size.width
                            let childWidth = CanonicalPageFlow.role(node) != nil || policy.alignment == .stretch
                                ? "max(1px,calc(100% - \(2 * policy.padding)px))"
                                : "min(\(basis)px,max(1px,calc(100% - \(2 * policy.padding)px)))"
                            let x = policy.alignment == .center ? "calc((100% - \(childWidth)) / 2)"
                                : policy.alignment == .end ? "calc(100% - \(policy.padding)px - \(childWidth))" : "\(policy.padding)px"
                            declarations += ["width:\(childWidth)", "left:\(x)"]
                        } else {
                            let basis = ResponsiveGeometryResolver.geometry(for: node, breakpoint: breakpoint, viewportWidth: width)?.size.width ?? 1
                            declarations += ["position:relative", "left:auto", "top:auto", "width:\(basis)px",
                                "flex:0 1 \(basis)px", "min-width:1px", "max-width:none"]
                        }
                    }
                    if let ownPolicy = snapshot.policies[node.id], ownPolicy.naturalFlow {
                        declarations.append("display:flow-root")
                    }
                    if node.kind == .stack, let ownPolicy = snapshot.policies[node.id], ownPolicy.axis == .horizontal {
                        let align = ownPolicy.alignment == .end ? "flex-end" : ownPolicy.alignment == .center ? "center" : ownPolicy.alignment == .stretch ? "stretch" : "flex-start"
                        declarations += ["display:flex", "flex-direction:row", "gap:\(ownPolicy.gap)px",
                            "padding:\(ownPolicy.padding)px", "align-items:\(align)"]
                    }
                    if CanonicalPageFlow.role(node) != nil, let parent, let policy {
                        if policy.naturalFlow {
                            let first = snapshot.firstFlowChild[parent.id]
                            declarations += ["position:relative", "top:auto", "left:\(policy.padding)px",
                                "width:max(1px,calc(100% - \(2 * policy.padding)px))",
                                "margin-top:\(first == node.id ? policy.padding : 0)px"]
                        }
                    }
                    if page.rootNodeIDs.contains(node.id) {
                        declarations.append("width:min(100%,\(frame.size.width)px)")
                    }
                    var values: [String: String] = [:], order: [String] = []
                    for declaration in declarations {
                        guard let separator = declaration.firstIndex(of: ":") else { continue }
                        let key = String(declaration[..<separator])
                        if values[key] == nil { order.append(key) }
                        values[key] = String(declaration[declaration.index(after: separator)...])
                    }
                    let compiled = order.compactMap { key in values[key].map { key + ":" + $0 } }.joined(separator: ";")
                    current.append("\(selector) { \(compiled); }")
                    if let settings = CanonicalPageChrome.navigationSettings(for: node, page: page) {
                        let links = node.childIDs.filter(snapshot.visibleIDs.contains).compactMap { byID[$0] }.filter(CanonicalPageFlow.isNavigationLink)
                        let count = links.count
                        guard count > 0 else {
                            current.append(".sf-page-navigation-\(node.id) { display:none; }")
                            continue
                        }
                        let padding = settings.id == node.id ? CanonicalPageFlow.padding(node, breakpoint: breakpoint, width: width) : 0
                        let alignment = settings.insertionStringProperty(CanonicalPageFlow.alignmentKey) ?? "start"
                        let justify = alignment == "end" ? "flex-end" : alignment == "center" ? "center" : "flex-start"
                        let gap = count > 1 ? "min(16px,max(0px,calc((100% - \(count)px) / \(count - 1))))" : "0px"
                        let itemWidth = "calc((100% - \(count - 1) * \(gap)) / \(count))"
                        current.append(".sf-page-navigation-\(node.id) { display:block;left:\(padding)px;top:\(padding)px;width:max(1px,calc(100% - \(2 * padding)px));height:\(min(32, max(1, frame.size.height - 2 * padding)))px; }")
                        current.append(".sf-page-navigation-\(node.id) .sf-nav-inline { gap:\(gap);justify-content:\(justify); }")
                        current.append(".sf-page-navigation-\(node.id) .sf-nav-inline a { width:\(alignment == "stretch" ? itemWidth : "min(160px,\(itemWidth))"); }")
                        current.append(".sf-page-navigation-\(node.id) .sf-nav-menu { margin-left:\(alignment == "end" || alignment == "center" ? "auto" : "0");margin-right:\(alignment == "center" ? "auto" : "0"); }")
                        let panelAlignment = alignment == "end" ? "right:0;left:auto;" : alignment == "center" ? "left:50%;transform:translateX(-50%);" : "left:0;right:auto;"
                        current.append(".sf-page-navigation-\(node.id) .sf-nav-menu[open] nav { \(panelAlignment) }")
                    }
                }
                let joined = current.joined(separator: "\n")
                rules.append(breakpoint == .desktop ? joined : "@media \(breakpoint == .tablet ? "(min-width:600px) and (width < 1024px)" : "(width < 600px)") { \(joined) }")
            }
        }
        return rules.isEmpty ? "" : (rules + [menuCSS]).joined(separator: "\n")
    }
}

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

struct ResolvedContainerLayoutPolicy: Sendable {
    let padding: Double
    let gap: Double
    let axis: ContainerLayoutAxis
    let alignment: ContainerLayoutAlignment
    let columns: Int
    let naturalFlow: Bool

    static func resolve(_ parent: DocumentNode, children: [DocumentNode], breakpoint: ResponsiveBreakpoint,
                        viewportWidth: Double?) -> Self {
        let boxPadding = DesignBoxStyleCommandRegistry.resolvedStyle(for: parent)?.padding
        let natural = parent.kind == .frame && children.contains { CanonicalPageFlow.role($0) != nil }
        let padding = natural ? (boxPadding ?? 0) : boxPadding ?? ResponsiveContainerLayoutResolver.value(
            for: .padding, node: parent, breakpoint: breakpoint, viewportWidth: viewportWidth)
            .flatMap { if case .number(let value) = $0.0 { value } else { nil } } ?? (parent.kind == .section ? 48 : 24)
        let gap: Double = [.section, .form, .frame].contains(parent.kind) ? 0 : (ResponsiveContainerLayoutResolver.value(
            for: .gap, node: parent, breakpoint: breakpoint, viewportWidth: viewportWidth)
            .flatMap { if case .number(let value) = $0.0 { value } else { nil } } ?? 24)
        let axis = parent.kind == .stack ? ResponsiveContainerLayoutResolver.value(
            for: .axis, node: parent, breakpoint: breakpoint, viewportWidth: viewportWidth)
            .flatMap { if case .axis(let value) = $0.0 { value } else { nil } } ?? .vertical : .vertical
        let alignment = parent.kind == .stack ? ResponsiveContainerLayoutResolver.value(
            for: .alignment, node: parent, breakpoint: breakpoint, viewportWidth: viewportWidth)
            .flatMap { if case .alignment(let value) = $0.0 { value } else { nil } } ?? .start : .start
        let columns = ResponsiveContainerLayoutResolver.value(for: .columns, node: parent,
            breakpoint: breakpoint, viewportWidth: viewportWidth)
            .flatMap { if case .number(let value) = $0.0 { Int(value) } else { nil } } ?? 2
        return .init(padding: padding, gap: gap, axis: axis, alignment: alignment, columns: max(1, columns), naturalFlow: natural)
    }
}

struct ConnectedPageLayoutSnapshot: Sendable {
    let frames: [NodeID: InsertionGeometry]
    let visibleIDs: Set<NodeID>
    let contentHeight: Double
    let policies: [NodeID: ResolvedContainerLayoutPolicy]
    let layoutChildren: [NodeID: [NodeID]]
    let childIndices: [NodeID: Int]
    let firstFlowChild: [NodeID: NodeID]

    init(page: DocumentPage, breakpoint: ResponsiveBreakpoint, width: Double) {
        let resolved = page.resolvedStructuralGeometry(breakpoint: breakpoint, viewportWidth: width)
        let visible = page.effectiveVisibleNodeIDs(breakpoint: breakpoint)
        frames = resolved
        visibleIDs = visible
        contentHeight = CanonicalPageFlow.contentHeight(page, frames: resolved, visibleIDs: visible)
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let children = Dictionary(uniqueKeysWithValues: page.nodes.map { node in
            (node.id, node.childIDs.filter { visible.contains($0) && byID[$0].map { !CanonicalPageFlow.isNavigationLink($0) } == true })
        })
        layoutChildren = children
        childIndices = Dictionary(uniqueKeysWithValues: children.values.flatMap { ids in ids.enumerated().map { ($0.element, $0.offset) } })
        firstFlowChild = Dictionary(uniqueKeysWithValues: children.compactMap { parent, ids in
            ids.first { byID[$0].flatMap(CanonicalPageFlow.role) != nil }.map { (parent, $0) }
        })
        policies = Dictionary(uniqueKeysWithValues: page.nodes.filter { $0.kind.acceptsAuthoredChildren }.map { node in
            (node.id, ResolvedContainerLayoutPolicy.resolve(node,
                children: node.childIDs.filter(visible.contains).compactMap { byID[$0] },
                breakpoint: breakpoint, viewportWidth: width))
        })
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
        // Match bounded flex shrink: a child clamped to one point consumes its
        // space before the remaining weights are distributed. A single sorted
        // pass avoids overflow and repeated full-array redistribution.
        var remaining = available, weight = total
        var clamped = Set<Int>()
        for index in bounded.indices.sorted(by: { bounded[$0] == bounded[$1] ? $0 < $1 : bounded[$0] < bounded[$1] }) {
            guard bounded[index] * remaining / weight < 1 else { break }
            clamped.insert(index)
            remaining -= 1
            weight -= bounded[index]
        }
        return bounded.indices.map { clamped.contains($0) ? 1 : bounded[$0] * remaining / max(1, weight) }
    }

    func resolvedStructuralGeometry(
        breakpoint: ResponsiveBreakpoint = .desktop,
        viewportWidth: Double? = nil
    ) -> [NodeID: InsertionGeometry] {
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let visibleNodeIDs = effectiveVisibleNodeIDs(breakpoint: breakpoint)
        let chromeOwners = Dictionary(nodes.compactMap { owner -> (NodeID, DocumentNode)? in
            CanonicalPageChrome.reference(CanonicalPageChrome.contentKey, on: owner).map { ($0, owner) }
        }, uniquingKeysWith: { first, _ in first })
        var result = Dictionary(uniqueKeysWithValues: nodes.compactMap { node in
            node.insertionGeometry.map {
                let base = $0.frame
                let resolved = ResponsiveGeometryResolver.frame(
                    for: node, base: base, breakpoint: breakpoint, viewportWidth: viewportWidth
                )
                return (node.id, InsertionGeometry(origin: resolved.origin, size: resolved.size))
            }
        })
        for parent in canonicalDepthFirstNodes() {
            let children = parent.childIDs.filter(visibleNodeIDs.contains).compactMap { nodesByID[$0] }
            let chromeOwner = chromeOwners[parent.id]
            let automaticChrome = chromeOwner.map { !CanonicalPageChrome.isCustom($0) } ?? false
            if let owner = chromeOwner, let bounds = result[owner.id]?.frame {
                let inset = CanonicalPageFlow.padding(owner, breakpoint: breakpoint, width: viewportWidth)
                result[parent.id] = .init(origin: .init(x: bounds.minX + inset, y: bounds.minY + inset),
                    size: .init(width: max(1, bounds.size.width - inset * 2), height: max(1, bounds.size.height - inset * 2)))
            }
            let policy = ResolvedContainerLayoutPolicy.resolve(parent, children: children,
                breakpoint: breakpoint, viewportWidth: viewportWidth)
            let flow = CanonicalPageFlow.ordered(children)
            let isRoot = rootNodeIDs.contains(parent.id)
            guard let parentGeometry = result[parent.id] ?? (isRoot && !flow.isEmpty
                ? .init(origin: .init(x: 0, y: 0), size: .init(width: CanonicalPageFlow.pageWidth(breakpoint, viewportWidth), height: 900)) : nil) else { continue }
            if policy.naturalFlow {
                let padding = policy.padding
                let width = max(1, (isRoot ? min(parentGeometry.size.width, CanonicalPageFlow.pageWidth(breakpoint, viewportWidth)) : parentGeometry.size.width) - 2 * padding)
                var y = parentGeometry.origin.y + padding
                for child in flow {
                    guard let geometry = result[child.id] else { continue }
                    result[child.id] = .init(origin: .init(x: parentGeometry.origin.x + padding, y: y),
                        size: .init(width: width, height: geometry.size.height))
                    y += geometry.size.height
                }
                // A padded Frame may still lay out ordinary children; managed
                // flow is its only vertical layout owner when present.
                continue
            }
            switch parent.kind {
            case .section, .stack, .form, .frame:
                let role = CanonicalPageFlow.role(parent)
                let hasNavigation = (role == .header || role == .footer)
                    && CanonicalPageChrome.reference(CanonicalPageChrome.navigationKey, on: parent) == nil
                let layoutChildren = hasNavigation ? children.filter { !CanonicalPageFlow.isNavigationLink($0) } : children
                // SF-0506 v1 adds a content inset to Frame and Section only.
                // It is an authored override of the existing Section layout
                // padding; other structural containers retain their own typed
                // layout resolver and an unstyled Frame remains absolute.
                let boxPadding = DesignBoxStyleCommandRegistry.resolvedStyle(for: parent)?.padding
                guard parent.kind != .frame || boxPadding != nil else { continue }
                let padding = policy.padding
                let gap = policy.gap
                let axis = policy.axis
                let alignment = policy.alignment
                let contentWidth = max(1, parentGeometry.size.width - (2 * padding))
                let contentHeight = max(1, parentGeometry.size.height - (2 * padding))
                let navigationHeight = hasNavigation && children.count != layoutChildren.count ? min(32, contentHeight) : 0
                let availableMain = max(
                    1,
                    (axis == .vertical ? contentHeight - navigationHeight : contentWidth) - Double(max(0, layoutChildren.count - 1)) * gap
                )
                let mainLengths = fittedMainAxisLengths(
                    layoutChildren.map { child in
                        if automaticChrome, axis == .horizontal, let owner = chromeOwner,
                           CanonicalPageChrome.reference(CanonicalPageChrome.navigationKey, on: owner) == child.id {
                            return max(1, availableMain - layoutChildren.filter { $0.id != child.id }
                                .reduce(0.0) { $0 + (result[$1.id]?.size.width ?? 1) })
                        }
                        guard let geometry = result[child.id] else { return 1 }
                        return axis == .vertical ? geometry.size.height : geometry.size.width
                    },
                    available: availableMain
                )
                var cursor = axis == .vertical
                    ? parentGeometry.origin.y + padding + navigationHeight
                    : parentGeometry.origin.x + padding
                for (childIndex, child) in layoutChildren.enumerated() {
                    guard var geometry = result[child.id] else { continue }
                    if axis == .vertical {
                        let width = alignment == .stretch || CanonicalPageFlow.role(child) != nil ? contentWidth : min(geometry.size.width, contentWidth)
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
                let padding = policy.padding
                let gap = policy.gap
                let columns = policy.columns
                let usableWidth = max(1, parentGeometry.size.width - 2 * padding - Double(columns - 1) * gap)
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
            case .text, .image, .button, .link, .component: break
            }
            if let settings = CanonicalPageChrome.navigationSettings(for: parent, page: self),
               settings.id == parent.id || !CanonicalPageChrome.isCustom(settings) {
                let links = children.filter(CanonicalPageFlow.isNavigationLink)
                let inset = settings.id == parent.id ? CanonicalPageFlow.padding(parent, breakpoint: breakpoint, width: viewportWidth) : 0
                let available = max(1, parentGeometry.size.width - 2 * inset)
                let height = min(32, max(1, parentGeometry.size.height - 2 * inset))
                let alignment = settings.insertionStringProperty(CanonicalPageFlow.alignmentKey) ?? (settings.id == parent.id ? "start" : "end")
                let navigationLayout = CanonicalPageFlow.navigationLayout(availableWidth: available, count: links.count, alignment: alignment)
                for (index, link) in links.enumerated() {
                    result[link.id] = .init(origin: .init(x: parentGeometry.origin.x + inset + navigationLayout.offset + Double(index) * (navigationLayout.width + navigationLayout.gap),
                                                        y: parentGeometry.origin.y + inset), size: .init(width: navigationLayout.width, height: height))
                }
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
