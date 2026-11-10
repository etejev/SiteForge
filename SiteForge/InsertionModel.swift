import CryptoKit
import Foundation

/// Presentation vocabulary only. Canonical keys, enum raw values and diagnostic
/// codes deliberately retain their stable technical names.
enum AuthoringLanguage {
    static let innerSpacing = "Inner spacing"
    static let itemSpacing = "Space between items"
    static let smoothScaling = "Smooth scaling"
    static let smoothScalingHelp = "Changes gradually as the screen gets wider. Explicit screen-size overrides still take priority."
    static let screenSize = "Screen size"
    static let screenSizeHelp = "Preview width selects Desktop, Tablet or Mobile. Inspector fields identify whether you are editing the base value or this screen size. Pan and zoom do not change website content."
    static let checkWebsite = "Check Website"
    static let appPreferencesScope = "SiteForge preferences · this Mac, not your website"
    static let staleDraft = "The selection, screen size or current value changed. Nothing changed; press Escape to cancel this draft before editing the new selection."
    static let editOriginalComponent = "Edit original component"
    static let backToCopy = "Back to this copy"
    static let useOriginalValue = "Use original value"
    static let componentRelationshipHelp = "Changes to the original update linked copies unless a value is set separately on that copy. An independent copy does not stay linked."
    static let removeCustomValueHelp = "Remove only this copy's custom value. An available original value is used; missing original data is not restored. Undo restores the exact removed value."
    static let colorOpacitySampleHelp = "Samples solid color and opacity for a linked reusable style. It does not copy gradients, tokens or border/shadow styles. Reuse Formatting copies the fuller Text Style or Appearance family."
    static let reviewCountsHelp = "Counts show objects with custom values at this screen size, not visual defects. Zero means no custom values in this review scope. Check boundary findings and preview separately. Smooth scaling counts property ranges."

    static func componentResetTitle(count: Int, visibilityOnly: Bool = false) -> String {
        "Reset \(visibilityOnly ? "visibility" : "copy") changes (\(count))"
    }

    static func reviewCustomizationCount(_ count: Int, name: String) -> String {
        "\(name): \(count) object\(count == 1 ? "" : "s")"
    }

    static func componentRecoverySummary(count: Int, originalAvailable: Bool = true) -> String {
        if count == 0 && !originalAvailable { return "Original component unavailable" }
        return "\(count) custom value\(count == 1 ? " needs" : "s need") attention"
    }

    static func removeCustomValuesTitle(count: Int) -> String {
        "Remove \(count) custom value\(count == 1 ? "" : "s")"
    }

    static func componentValueName(kind: String) -> String {
        switch kind {
        case "text": "Text"
        case "visibility": "Visibility"
        case "choice": "Image fit"
        case "media": "Image"
        case "action": "Destination"
        case "slot": "Default contents"
        default: "Property"
        }
    }

    static func sizing(_ mode: CanonicalSizingMode) -> String {
        switch mode {
        case .fixed: "Exact size"
        case .fill: "Fill available space"
        case .hug: "Fit content"
        }
    }

    static func propertySource(_ origin: PropertyOrigin) -> String {
        origin == .authored ? "Set here" : "Default"
    }

    static func componentSource(isOverride: Bool) -> String {
        isOverride ? "Set here · this instance" : "Uses component default"
    }
}

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
        switch self { case .desktop: "1024 CSS px and wider"; case .tablet: "600 to below 1024 CSS px"; case .mobile: "below 600 CSS px" }
    }
    static func resolving(width: Double) -> ResponsiveBreakpoint {
        guard width.isFinite else { return .desktop }
        if width < 600 { return .mobile }
        if width < 1024 { return .tablet }
        return .desktop
    }
    /// Same half-open ranges for fractional CSS widths; integer max-width
    /// aliases leave gaps between 599/600 and 1023/1024.
    var cssMediaCondition: String? {
        switch self {
        case .desktop: nil
        case .tablet: "(min-width: 600px) and (width < 1024px)"
        case .mobile: "(width < 600px)"
        }
    }
}

enum ResponsiveGeometrySource: Equatable, Sendable {
    case baseDesktop
    case fluid
    case override(ResponsiveBreakpoint)

    var label: String {
        switch self {
        case .baseDesktop: "Uses Desktop"
        case .fluid: AuthoringLanguage.smoothScaling
        case .override(let value): "Set here · \(value.title)"
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
        switch self { case .padding: AuthoringLanguage.innerSpacing; case .gap: AuthoringLanguage.itemSpacing; case .axis: "Direction"; case .alignment: "Alignment"; case .columns: "Columns" }
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
        switch self { case .baseDesktop: breakpoint == .desktop ? "Desktop base" : "Uses Desktop"; case .override(let value): "Set here · \(value.title)" }
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
            let query = "@media \(breakpoint.cssMediaCondition ?? "all")"
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
    /// One continuous expression for connected CSS rules that themselves
    /// span the 768-point fluid anchor. Both clamps reuse the existing emitter
    /// math; subtracting the shared anchor prevents double-counting it.
    static func expression(for value: CanonicalFluidValue, precision: Int = 3) -> String? {
        guard value.isValid, [3, 9].contains(precision) else { return nil }
        let lower = segment(start: value.minimum, end: value.preferred,
            from: CanonicalFluidValue.lowerViewport, to: CanonicalFluidValue.preferredViewport, precision: precision)
        let upper = segment(start: value.preferred, end: value.maximum,
            from: CanonicalFluidValue.preferredViewport, to: CanonicalFluidValue.upperViewport, precision: precision)
        return "calc(\(lower) + \(upper) - \(number(value.preferred, precision: precision))px)"
    }
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

    private static func segment(start: Double, end: Double, from lower: Double, to upper: Double, precision: Int = 3) -> String {
        guard end != start else { return "\(number(start, precision: precision))px" }
        let slope = (end - start) / (upper - lower)
        let vw = slope * 100
        let intercept = start - slope * lower
        let offset = intercept < 0
            ? "- \(number(abs(intercept), precision: precision))px"
            : "+ \(number(intercept, precision: precision))px"
        return "clamp(\(number(start, precision: precision))px, calc(\(number(vw, precision: precision))vw \(offset)), \(number(end, precision: precision))px)"
    }

    private static func number(_ value: Double, precision: Int = 3) -> String {
        let scale = pow(10.0, Double(precision))
        let rounded = (value * scale).rounded() / scale
        var output = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), precision, rounded)
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

struct InsertionValidationContext: Equatable, Sendable {
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

/// Closed scalar intent, not sampled geometry or a second layout engine.
/// The CSS path and compatibility proof share the existing cascade winners.
enum ConnectedOutputLength: Equatable, Sendable {
    case fixed(Double), fluid(CanonicalFluidValue)
    var minimum: Double { switch self { case .fixed(let value): value; case .fluid(let value): value.minimum } }
    var maximum: Double { switch self { case .fixed(let value): value; case .fluid(let value): value.maximum } }
    var css: String {
        switch self {
        case .fixed(let value): "\(value)px"
        case .fluid(let value): StaticFluidValueOutputEmitter.expression(for: value, precision: 9) ?? "0px"
        }
    }
    func resolved(at width: Double) -> Double {
        switch self { case .fixed(let value): value; case .fluid(let value): value.resolved(viewportWidth: width) ?? 0 }
    }
    func bounds(in breakpoint: ResponsiveBreakpoint) -> (minimum: Double, maximum: Double) {
        // Half-open interval endpoints are safe suprema for the closed,
        // monotonic curve. Desktop's tail is clamped after the upper anchor.
        let lower = breakpoint == .desktop ? 1024.0 : breakpoint == .tablet ? 600.0 : 0.0
        let upper = breakpoint == .mobile ? 600.0 : breakpoint == .tablet ? 1024.0 : CanonicalFluidValue.upperViewport
        return (resolved(at: lower), resolved(at: upper))
    }
}

enum ConnectedFluidOutputPolicy {
    typealias Failure = (code: String, explanation: String, repair: String)
    static let targets: [FluidValueTarget] = [.width, .height, .padding, .gap]
    static func needsAdapter(_ page: DocumentPage) -> Bool {
        page.nodes.contains { CanonicalPageFlow.role($0) != nil }
            && page.nodes.contains { node in targets.contains { CanonicalFluidValueCodec.value(for: $0, node: node) != nil } }
    }
    static func dimension(_ node: DocumentNode, _ dimension: SizingDimension, breakpoint: ResponsiveBreakpoint) -> ConnectedOutputLength {
        let field: GeometryInspectorField = dimension == .width ? .width : .height
        let width = CanonicalPageFlow.pageWidth(breakpoint, nil)
        let value = ResponsiveGeometryResolver.value(for: field, node: node, breakpoint: breakpoint, viewportWidth: width)
        let target: FluidValueTarget = field == .width ? .width : .height
        if value?.2 == .fluid, let fluid = CanonicalFluidValueCodec.value(for: target, node: node)?.0 { return .fluid(fluid) }
        return .fixed(value?.0 ?? (field == .width ? node.insertionGeometry?.size.width : node.insertionGeometry?.size.height) ?? 1)
    }
    static func spacing(_ node: DocumentNode, field: ContainerLayoutField,
                        policy: ResolvedContainerLayoutPolicy, breakpoint: ResponsiveBreakpoint) -> ConnectedOutputLength {
        let fallback = field == .padding ? policy.padding : policy.gap
        if field == .padding, DesignBoxStyleCommandRegistry.resolvedStyle(for: node)?.padding != nil { return .fixed(fallback) }
        if field == .gap && [.section, .frame, .form].contains(node.kind) { return .fixed(0) }
        let width = CanonicalPageFlow.pageWidth(breakpoint, nil)
        if ResponsiveContainerLayoutResolver.value(for: field, node: node, breakpoint: breakpoint, viewportWidth: width)?.2 == .fluid,
           let value = CanonicalFluidValueCodec.value(for: field == .padding ? .padding : .gap, node: node)?.0 { return .fluid(value) }
        return .fixed(fallback)
    }
    static func wrapperClass(_ id: NodeID) -> String { "sf-layout-" + id.description }
    static func wrapperIDs(_ page: DocumentPage) -> Set<NodeID> {
        guard needsAdapter(page) else { return [] }
        return Set(page.nodes.filter { [.frame, .section, .stack, .grid].contains($0.kind) }.map(\.id))
    }
    static func failures(_ page: DocumentPage) -> [NodeID: Failure] {
        guard needsAdapter(page) else { return [:] }
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        var failures: [NodeID: Failure] = [:]
        func reject(_ node: DocumentNode, _ suffix: String, _ reason: String, _ repair: String) {
            if failures[node.id] == nil { failures[node.id] = ("page-flow-fluid-" + suffix, reason, repair) }
        }
        for breakpoint in ResponsiveBreakpoint.allCases {
            let width = CanonicalPageFlow.pageWidth(breakpoint, nil)
            let visible = page.effectiveVisibleNodeIDs(breakpoint: breakpoint)
            let automaticScope = ResponsiveSizingLayout.scope(page: page, breakpoint: breakpoint, width: width)
            var childrenCache: [NodeID: [DocumentNode]] = [:]
            var policyCache: [NodeID: ResolvedContainerLayoutPolicy] = [:]
            var heightBudgetCache: [NodeID: Double] = [:]
            var allocationCache: [NodeID: Bool] = [:]
            func children(_ node: DocumentNode) -> [DocumentNode] {
                if let cached = childrenCache[node.id] { return cached }
                let result = node.childIDs.filter(visible.contains).compactMap { byID[$0] }.filter { !CanonicalPageFlow.isNavigationLink($0) && $0.insertionGeometry != nil }
                childrenCache[node.id] = result; return result
            }
            func policy(_ node: DocumentNode) -> ResolvedContainerLayoutPolicy {
                if let cached = policyCache[node.id] { return cached }
                let result = ResolvedContainerLayoutPolicy.resolve(node, children: children(node), breakpoint: breakpoint, viewportWidth: width)
                policyCache[node.id] = result; return result
            }
            func neededHeight(_ node: DocumentNode) -> Double {
                if let cached = heightBudgetCache[node.id] { return cached }
                let p = policy(node), items = children(node)
                let result = items.reduce(0.0) { $0 + dimension($1, .height, breakpoint: breakpoint).bounds(in: breakpoint).maximum }
                    + Double(max(0, items.count - 1)) * spacing(node, field: .gap, policy: p, breakpoint: breakpoint).bounds(in: breakpoint).maximum
                    + 2 * spacing(node, field: .padding, policy: p, breakpoint: breakpoint).bounds(in: breakpoint).maximum
                heightBudgetCache[node.id] = result; return result
            }
            // This is a conservative range proof, not a sample-based browser
            // claim. Unknown intrinsic bounds or possible ancestor compression
            // keep Grid row allocation explicitly unsupported.
            func uncompressed(_ node: DocumentNode, visited: Set<NodeID> = []) -> Bool {
                guard !visited.contains(node.id), visited.count < 256 else { return false }
                if let cached = allocationCache[node.id] { return cached }
                let answer: Bool = {
                    guard case .node(let id) = node.parent, let parent = byID[id] else { return true }
                    let p = policy(parent)
                    if p.naturalFlow && CanonicalPageFlow.role(node) != nil { return true }
                    guard parent.kind != .grid, uncompressed(parent, visited: visited.union([node.id])) else { return false }
                    if p.axis == .horizontal {
                        let pad = spacing(parent, field: .padding, policy: p, breakpoint: breakpoint).bounds(in: breakpoint).maximum
                        return dimension(node, .height, breakpoint: breakpoint).bounds(in: breakpoint).maximum <= dimension(parent, .height, breakpoint: breakpoint).bounds(in: breakpoint).minimum - 2 * pad
                    }
                    return neededHeight(parent) <= dimension(parent, .height, breakpoint: breakpoint).bounds(in: breakpoint).minimum
                }()
                allocationCache[node.id] = answer; return answer
            }
            for node in page.nodes where visible.contains(node.id) {
                let p = policy(node), items = children(node)
                if page.rootNodeIDs.contains(node.id), !p.naturalFlow {
                    reject(node, "root-flow", "This fluid connected page has no root-owned flow containing block.", "Use the existing connected Section/Header/Footer controls at the page root, or keep native Preview.")
                }
                if page.rootNodeIDs.contains(node.id), let geometry = node.insertionGeometry,
                   geometry.origin.x != 0 || geometry.origin.y != 0 {
                    reject(node, "root-origin", "A displaced page root needs a browser containing-origin policy.", "Restore the page root origin explicitly or keep native Preview; no object coordinates are rewritten.")
                }
                if page.rootNodeIDs.contains(node.id), CanonicalFluidValueCodec.value(for: .height, node: node) != nil {
                    reject(node, "root-height", "A fluid page-root paint height is distinct from connected document flow height.", "Keep native Preview or restore the prior root with Undo; author supported height on a connected Section instead.")
                }
                if CanonicalPageFlow.role(node) != nil, case .node(let parentID) = node.parent,
                   let parent = byID[parentID], !policy(parent).naturalFlow,
                   CanonicalSizingConstraints.effectiveMode(.width, node: parent, breakpoint: breakpoint, width: width) == .fill {
                    reject(node, "managed-fill-width", "This nested role retains an earlier containing allocation under automatic Fill width.", "Use a fixed/fluid containing width or keep native Preview until coupled role allocation is supported.")
                }
                if p.naturalFlow, !page.rootNodeIDs.contains(node.id), items.contains(where: { CanonicalPageFlow.role($0) == nil }) {
                    reject(node, "mixed-free-flow", "Nested mixed free/flow children retain world offsets not represented by dynamic browser flow.", "Keep the free content in an explicit padded container or keep native Preview; authored coordinates are not rewritten.")
                }
                if p.naturalFlow, !page.rootNodeIDs.contains(node.id),
                   CanonicalSizingConstraints.effectiveMode(.height, node: node, breakpoint: breakpoint, width: width) != .hug {
                    let needed = items.reduce(0.0) { $0 + dimension($1, .height, breakpoint: breakpoint).bounds(in: breakpoint).maximum }
                        + 2 * spacing(node, field: .padding, policy: p, breakpoint: breakpoint).bounds(in: breakpoint).maximum
                    if needed > dimension(node, .height, breakpoint: breakpoint).bounds(in: breakpoint).minimum {
                        reject(node, "nested-flow-overflow", "Nested connected descendants can outgrow this fixed containing Frame across the fluid range.", "Increase its height or explicitly use supported Hug sizing; native intent is retained until then.")
                    }
                }
                if automaticScope.affected.contains(node.id), !p.naturalFlow, !items.isEmpty {
                    let needed = neededHeight(node)
                    if p.axis == .horizontal || (node.kind != .grid && needed > dimension(node, .height, breakpoint: breakpoint).bounds(in: breakpoint).minimum) {
                        reject(node, "intrinsic-initial-fit", "Automatic sizing can inherit an initial fitted allocation in this dynamic container.", "Use a vertical container with enough fixed fallback height, or keep native Preview. No browser sample substitutes for the retained intrinsic intent.")
                    }
                }
                if targets.contains(where: { CanonicalFluidValueCodec.value(for: $0, node: node) != nil }), node.insertionGeometry == nil {
                    reject(node, "missing-geometry", "A fluid binding has no complete authored geometry.", "Restore the original geometry with Undo or remove the inapplicable binding explicitly.")
                }
                if node.kind == .form { reject(node, "form-containing-layout", "Fluid connected Form field placement is not represented by this adapter.", "Keep native Preview or move fluid content outside the Form; do not discard field data.") }
                if node.kind == .frame && !page.rootNodeIDs.contains(node.id) && !p.naturalFlow && DesignBoxStyleCommandRegistry.resolvedStyle(for: node)?.padding == nil && !items.isEmpty {
                    reject(node, "free-containing-layout", "An unpadded free Frame retains world-positioned children; dynamic containing offsets are not a browser flow.", "Use the existing explicit padding/connected-layout controls, or keep native Preview. Child coordinates are not rewritten.")
                }
                let sizing = CanonicalSizingConstraints.resolved(for: node)
                if sizing.aspectEnabled && [.width, .height].contains(where: { CanonicalFluidValueCodec.value(for: $0, node: node) != nil }) {
                    reject(node, "aspect-coupling", "Aspect-locked fluid dimensions need an explicit coupled resolution policy.", "Disable aspect lock or reset the conflicting fluid dimension through Layout; existing intent is retained.")
                }
                if CanonicalSizingConstraints.effectiveMode(.height, node: node, breakpoint: breakpoint, width: width) == .fill {
                    reject(node, "fill-height", "Fill-height participation with dynamic connected ancestors is not covered by this adapter.", "Use an explicit height or supported Hug height through Layout, or keep native Preview.")
                }
                if let content = CanonicalPageChrome.reference(CanonicalPageChrome.contentKey, on: node) {
                    if node.childIDs != [content] { reject(node, "chrome-direct-children", "Extra direct chrome children conflict with the managed content bounds.", "Move custom content into the existing editable Content Stack before exporting.") }
                    if CanonicalSizingConstraints.effectiveMode(.height, node: node, breakpoint: breakpoint, width: width) == .hug {
                        reject(node, "chrome-hug-cycle", "Chrome Hug height and its owner-sized Content Stack form an unresolved intrinsic cycle.", "Choose explicit or fluid Header/Footer height; keep the Content Stack and title editable.")
                    }
                } else if [.header, .footer].contains(CanonicalPageFlow.role(node)), node.childIDs.compactMap({ byID[$0] }).contains(where: CanonicalPageFlow.isNavigationLink) {
                    reject(node, "legacy-navigation", "Legacy direct navigation needs editable content ownership for fluid connected output.", "Use Add Editable Title and Navigation in the existing Header/Footer settings, then preflight again.")
                }
                if node.kind == .grid {
                    var rowMax: [Double] = []
                    for (index, child) in items.enumerated() {
                        if index % p.columns == 0 { rowMax.append(1) }
                        if CanonicalSizingConstraints.effectiveMode(.height, node: child, breakpoint: breakpoint, width: width) != .fixed {
                            reject(node, "grid-intrinsic-rows", "Grid rows with intrinsic/Fill children need an additional dynamic track proof.", "Use explicit child heights or a Stack for this content; keep native Preview for intrinsic Grid rows.")
                        }
                        rowMax[rowMax.count - 1] = max(rowMax[rowMax.count - 1], dimension(child, .height, breakpoint: breakpoint).bounds(in: breakpoint).maximum)
                    }
                    let pad = spacing(node, field: .padding, policy: p, breakpoint: breakpoint).bounds(in: breakpoint).maximum
                    let gap = spacing(node, field: .gap, policy: p, breakpoint: breakpoint).bounds(in: breakpoint).maximum
                    let required = rowMax.reduce(0, +) + Double(max(0, rowMax.count - 1)) * gap + 2 * pad
                    if !uncompressed(node) || required > dimension(node, .height, breakpoint: breakpoint).bounds(in: breakpoint).minimum {
                        reject(node, "grid-row-compression", "Grid row maxima cannot be proven to fit across the fluid range and containing allocation.", "Increase the containing/ Grid height, reduce spacing or use Stack flow; original values remain unchanged.")
                    }
                }
                if p.axis == .horizontal {
                    let fills = items.filter { CanonicalSizingConstraints.effectiveMode(.width, node: $0, breakpoint: breakpoint, width: width) == .fill }
                    if fills.count > 1 && fills.contains(where: { let s = CanonicalSizingConstraints.resolved(for: $0); return s.minWidth != nil || s.maxWidth != nil }) {
                        reject(node, "bounded-fill-distribution", "Multiple bounded Fill siblings do not share the same browser redistribution rule.", "Use unbounded equal Fill widths, one Fill child, or explicit widths; keep native Preview otherwise.")
                    }
                }
            }
        }
        return failures
    }
}

enum ConnectedPageOutput {
    // Keep the popup inside details' own content layout. Absolute descendants
    // of closed details retained painted panels in the supported Safari build.
    // An overlapping grid row preserves page flow and gives open content a real
    // intrinsic hit box; older engines retain the existing positioned fallback.
    static let menuCSS = """
    .sf-connected-page { position:relative;width:100%;min-height:100vh;overflow:hidden; }
    body.sf-connected-body { margin:0; }
    .sf-page-navigation { position:absolute;box-sizing:border-box;font:14px system-ui; }
    :where(.sf-page-navigation a) { color:inherit;text-decoration:none; }
    .sf-nav-inline { display:flex;align-items:center;min-width:0; }
    .sf-nav-inline a { flex:none;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis; }
    .sf-nav-menu { display:none;position:relative;width:max-content;max-width:100%; }
    .sf-nav-menu summary { list-style:none;cursor:pointer;white-space:nowrap; }
    .sf-nav-menu summary::-webkit-details-marker { display:none; }
    @media (width < 600px) { .sf-nav-responsive { display:none; } .sf-nav-menu { display:block; } .sf-nav-menu[open] nav { display:flex;position:absolute;z-index:100;min-width:160px;max-width:min(320px,80vw);max-height:50vh;overflow:auto;flex-direction:column;gap:8px;padding:12px;background:Canvas;color:CanvasText;box-shadow:0 4px 16px #0003; } footer .sf-nav-menu[open] nav { bottom:100%; } }
    @supports selector(details::details-content) {
      @media (width < 600px) {
        .sf-nav-menu { line-height:normal; }
        .sf-nav-menu[open] { display:grid;grid-template-columns:100%;grid-template-rows:1lh;height:1lh; }
        .sf-nav-menu > summary { grid-area:1 / 1;align-self:start; }
        .sf-nav-menu[open]::details-content { grid-area:1 / 1;align-self:start;justify-self:var(--sf-menu-panel-alignment,start);width:max-content;max-width:min(320px,80vw);margin-block-start:1lh;position:relative;z-index:100; }
        .sf-nav-menu[open] nav { position:static; }
        footer .sf-nav-menu[open]::details-content { align-self:end;margin-block-start:0;margin-block-end:1lh; }
      }
    }
    """
    static let menuScript = """
    (function(){
    const selector='details[data-siteforge-navigation]';
    function close(menu,restore){menu.open=false;const summary=menu.querySelector('summary');if(summary){summary.setAttribute('aria-expanded','false');if(restore)summary.focus();}}
    document.addEventListener('toggle',function(event){const menu=event.target;if(!(menu instanceof HTMLDetailsElement)||!menu.matches(selector))return;const summary=menu.querySelector('summary');if(summary)summary.setAttribute('aria-expanded',String(menu.open));if(menu.open)document.querySelectorAll(selector+'[open]').forEach(function(other){if(other!==menu)close(other,false);});},true);
    document.addEventListener('keydown',function(event){if(event.key!=='Escape')return;const menu=(event.target instanceof Element?event.target.closest(selector):null)||document.querySelector(selector+'[open]');if(menu&&menu.open){close(menu,true);event.preventDefault();}});
    document.addEventListener('click',function(event){const target=event.target;if(!(target instanceof Element))return;document.querySelectorAll(selector+'[open]').forEach(function(menu){if(!menu.contains(target)||target.closest('[data-siteforge-nav-link]'))close(menu,false);});});
    document.addEventListener('focusin',function(event){if(event.target===document.body||event.target===document.documentElement)return;document.querySelectorAll(selector+'[open]').forEach(function(menu){if(!menu.contains(event.target))close(menu,false);});});
    window.matchMedia('(width < 600px)').addEventListener('change',function(event){if(event.matches)return;document.querySelectorAll(selector+'[open]').forEach(function(menu){const focused=menu.contains(document.activeElement);close(menu,false);if(focused){const owner=menu.closest('.sf-page-navigation');const first=owner&&Array.from(owner.querySelectorAll('.sf-nav-inline a[href]')).find(function(link){return link.getClientRects().length>0;});if(first)first.focus();else document.body.focus();}});});
    }());
    """
    static func css(pages: [DocumentPage], colorTokens: [LocalColorToken] = []) -> String {
        var rules: [String] = []
        let availablePageIDs = Set(pages.filter { $0.role != .componentDefinition }.map(\.id))
        for page in pages where page.usesConnectedOutput {
            if ConnectedFluidOutputPolicy.needsAdapter(page) {
                rules += fluidFlowRules(page, colorTokens: colorTokens, availablePageIDs: availablePageIDs)
                rules += automaticMenuRules(page, usesWrapper: true, availablePageIDs: availablePageIDs)
                continue
            }
            let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
            let automaticNavigationIDs = Set(page.nodes.filter { !CanonicalPageChrome.isCustom($0) }
                .compactMap { CanonicalPageChrome.reference(CanonicalPageChrome.navigationKey, on: $0) })
            for breakpoint in ResponsiveBreakpoint.allCases {
                let width = CanonicalPageFlow.pageWidth(breakpoint, nil)
                let snapshot = ConnectedPageLayoutSnapshot(page: page, breakpoint: breakpoint, width: width,
                    availablePageIDs: availablePageIDs)
                let automatic = page.hasAutomaticSizing
                var current = [".sf-page-\(page.id) { height:\(automatic ? "auto" : "\(snapshot.contentHeight)px"); }"]
                for node in page.canonicalDepthFirstNodes() {
                    let selector = CanonicalCSSRule.selector(for: node.id)
                    if CanonicalPageFlow.isNavigationLink(node) {
                        current.append(".sf-nav-link-\(node.id) { display:\(snapshot.visibleIDs.contains(node.id) ? "block" : "none"); }")
                        continue
                    }
                    guard snapshot.visibleIDs.contains(node.id) else {
                        current.append("\(selector)\(node.kind == .text ? "[data-siteforge-node]" : "") { display:none; }")
                        continue
                    }
                    let frame = snapshot.frames[node.id]
                    if page.rootNodeIDs.contains(node.id), frame == nil {
                        // The real authored page root owns its background.
                        // Give that root the viewport minimum too, rather than
                        // leaving unpainted space in a decorative wrapper.
                        current.append("\(selector) { display:flow-root;position:relative;left:0;top:0;width:100%;height:\(automatic ? "auto" : "\(snapshot.contentHeight)px");min-height:100vh;box-sizing:border-box;padding:0;margin:0; }")
                        continue
                    }
                    guard let frame else {
                        // Retain semantic identity without creating layout
                        // space for a node the native renderer cannot paint.
                        current.append("\(selector)\(node.kind == .text ? "[data-siteforge-node]" : "") { display:none; }")
                        continue
                    }
                    let parentID: NodeID? = { if case .node(let id) = node.parent { id } else { nil } }()
                    let parentFrame = parentID.flatMap { snapshot.frames[$0] }
                    let parent = parentID.flatMap { byID[$0] }
                    let policy = parentID.flatMap { snapshot.policies[$0] }
                    let localX = frame.origin.x - (parentFrame?.origin.x ?? 0)
                    let localY = frame.origin.y - (parentFrame?.origin.y ?? 0)
                    var declarations = ["display:\([.button, .link].contains(node.kind) ? "flex" : "block")", "position:absolute", "box-sizing:border-box", "padding:0", "margin:0",
                        "left:\(localX)px", "top:\(localY)px", "width:\(frame.size.width)px", "height:\(frame.size.height)px"]
                    if let parent, let policy,
                       parent.kind == .grid || parent.kind == .stack || parent.kind == .section || parent.kind == .form
                        || (parent.kind == .frame && !policy.naturalFlow && DesignBoxStyleCommandRegistry.resolvedStyle(for: parent)?.padding != nil) {
                        let index = snapshot.childIndices[node.id] ?? 0
                        if parent.kind == .grid {
                            let cell = "calc(max(1px,calc(100% - \(2 * policy.padding + Double(policy.columns - 1) * policy.gap)px)) / \(policy.columns))"
                            if CanonicalSizingConstraints.dimensionResolution(.width, node: node,
                                breakpoint: breakpoint, width: width).numericSource == nil { declarations.append("width:\(cell)") }
                            declarations.append("left:calc(\(policy.padding)px + \(index % policy.columns) * (\(cell) + \(policy.gap)px))")
                        } else if policy.axis == .vertical {
                            let basis = ResponsiveGeometryResolver.geometry(for: node, breakpoint: breakpoint, viewportWidth: width)?.size.width ?? frame.size.width
                            let managedChromeContent = CanonicalPageChrome.reference(CanonicalPageChrome.contentKey, on: parent) == node.id
                            let childWidth = CanonicalPageFlow.role(node) != nil || policy.alignment == .stretch || managedChromeContent
                                ? "max(1px,calc(100% - \(2 * policy.padding)px))"
                                : "min(\(basis)px,max(1px,calc(100% - \(2 * policy.padding)px)))"
                            let x = policy.alignment == .center ? "calc((100% - \(childWidth)) / 2)"
                                : policy.alignment == .end ? "calc(100% - \(policy.padding)px - \(childWidth))" : "\(policy.padding)px"
                            declarations += ["width:\(childWidth)", "left:\(x)"]
                        } else {
                            let basis = ResponsiveGeometryResolver.geometry(for: node, breakpoint: breakpoint, viewportWidth: width)?.size.width ?? 1
                            declarations += ["position:relative", "left:auto", "top:auto", "width:\(basis)px",
                                "flex:0 1 \(basis)px", "min-width:1px", "max-width:none"]
                            if automaticNavigationIDs.contains(node.id) {
                                // The same automatic chrome owner gives this
                                // child the remaining native row width. Its
                                // stored default width is not a fixed basis.
                                declarations += ["width:auto", "flex:1 1 0px"]
                            }
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
                    declarations += automaticSizingDeclarations(node: node, parent: parent,
                        snapshot: snapshot, breakpoint: breakpoint, width: width, localX: localX, localY: localY)
                    // Connected layout rules come after generic fluid CSS.
                    // Do not pin a winning fluid value to one sampled preset.
                    for target in [FluidValueTarget.width, .height, .padding, .gap] {
                        guard let value = CanonicalFluidValueCodec.value(for: target, node: node)?.0,
                              let expression = StaticFluidValueOutputEmitter.expression(for: value) else { continue }
                        let wins: Bool
                        switch target {
                        case .width, .height:
                            wins = CanonicalSizingConstraints.dimensionResolution(target == .width ? .width : .height,
                                node: node, breakpoint: breakpoint, width: width).numericSource == .fluid
                        case .padding:
                            wins = DesignBoxStyleCommandRegistry.resolvedStyle(for: node)?.padding == nil
                                && ResponsiveContainerLayoutResolver.value(for: .padding, node: node, breakpoint: breakpoint, viewportWidth: width)?.2 == .fluid
                        case .gap:
                            wins = ResponsiveContainerLayoutResolver.value(for: .gap, node: node, breakpoint: breakpoint, viewportWidth: width)?.2 == .fluid
                        default: wins = false
                        }
                        if wins { declarations.append(target.rawValue + ":" + expression) }
                    }
                    var values: [String: String] = [:], order: [String] = []
                    for declaration in declarations {
                        guard let separator = declaration.firstIndex(of: ":") else { continue }
                        let key = String(declaration[..<separator])
                        if values[key] == nil { order.append(key) }
                        values[key] = String(declaration[declaration.index(after: separator)...])
                    }
                    if node.kind == .text, let height = values["height"] {
                        values["--sf-text-height"] = height; order.append("--sf-text-height")
                    }
                    let compiled = order.compactMap { key in values[key].map { key + ":" + $0 } }.joined(separator: ";")
                    current.append("\(selector) { \(compiled); }")
                    if let settings = CanonicalPageChrome.navigationSettings(for: node, page: page) {
                        current += navigationMenuRules(surface: node, settings: settings, page: page,
                            breakpoint: breakpoint, availablePageIDs: availablePageIDs)
                        let links = node.childIDs.filter(snapshot.visibleIDs.contains).compactMap { byID[$0] }.filter(CanonicalPageFlow.isNavigationLink)
                        let count = links.count
                        guard count > 0 else {
                            current.append(".sf-page-navigation-\(node.id) { display:none; }")
                            continue
                        }
                        let padding = settings.id == node.id ? CanonicalPageFlow.padding(node, breakpoint: breakpoint, width: width) : 0
                        let alignment = CanonicalPageChrome.navigationAlignment(surface: node, settings: settings)
                        let justify = alignment == "end" ? "flex-end" : alignment == "center" ? "center" : "flex-start"
                        let authoredGap = CanonicalPageChrome.navigationGap(surface: node, settings: settings, breakpoint: breakpoint, width: width)
                        let gap = count > 1 ? "min(\(authoredGap)px,max(0px,calc((100% - \(count)px) / \(count - 1))))" : "0px"
                        let itemWidth = "calc((100% - \(count - 1) * \(gap)) / \(count))"
                        current.append(".sf-page-navigation-\(node.id) { display:block;left:\(padding)px;top:\(padding)px;width:max(1px,calc(100% - \(2 * padding)px));height:\(min(32, max(1, frame.size.height - 2 * padding)))px; }")
                        current.append(".sf-page-navigation-\(node.id) .sf-nav-inline { gap:\(gap);justify-content:\(justify); }")
                        current.append(".sf-page-navigation-\(node.id) .sf-nav-inline a { width:\(alignment == "stretch" ? itemWidth : "min(160px,\(itemWidth))"); }")
                        current.append(".sf-page-navigation-\(node.id) .sf-nav-menu { margin-left:\(alignment == "end" || alignment == "center" ? "auto" : "0");margin-right:\(alignment == "center" ? "auto" : "0"); }")
                        if breakpoint == .mobile {
                            // The automatic title may retain a wider authored
                            // box than its glyphs. Keep the menu intrinsic and
                            // align its full hit area, not a wrapped fragment,
                            // within the remaining navigation edge.
                            current.append(".sf-page-navigation-\(node.id) { display:flex;justify-content:\(justify); }")
                            current.append(".sf-page-navigation-\(node.id) .sf-nav-menu { flex:none;max-width:none;margin:0; }")
                        }
                        let panelAlignment = alignment == "end" ? "end" : alignment == "center" ? "center" : "start"
                        current.append(".sf-page-navigation-\(node.id) .sf-nav-menu { --sf-menu-panel-alignment:\(panelAlignment); }")
                        let fallbackPanel = alignment == "end" ? "right:0;left:auto;" : alignment == "center" ? "left:50%;transform:translateX(-50%);" : "left:0;right:auto;"
                        current.append("@supports not selector(details::details-content) { .sf-page-navigation-\(node.id) .sf-nav-menu[open] nav { \(fallbackPanel) } }")
                        if let color = CanonicalPageChrome.navigationForeground(surface: node, page: page, tokens: colorTokens) {
                            current.append(".sf-page-navigation-\(node.id) .sf-nav-menu > summary { color:\(color.hexadecimalRGBA); }")
                        }
                        if let color = CanonicalPageChrome.opaqueNavigationSurface(surface: node, page: page, tokens: colorTokens) {
                            current.append(".sf-page-navigation-\(node.id) .sf-nav-menu[open] nav { background:\(color.hexadecimalRGBA); }")
                        }
                    }
                }
                let joined = current.joined(separator: "\n")
                rules.append(breakpoint == .desktop ? joined : "@media \(breakpoint.cssMediaCondition ?? "all") { \(joined) }")
            }
            rules += automaticMenuRules(page, usesWrapper: false, availablePageIDs: availablePageIDs)
        }
        return rules.isEmpty ? "" : (rules + [menuCSS]).joined(separator: "\n")
    }

    static func navigationMenuRules(surface: DocumentNode, settings: DocumentNode, page: DocumentPage,
                                    breakpoint: ResponsiveBreakpoint, availablePageIDs: Set<PageID>) -> [String] {
        let showsMenu = breakpoint == .mobile
            && settings.insertionProperty(CanonicalPageFlow.hamburgerKey)?.value == .boolean(true)
            && CanonicalPageChrome.hasUsableNavigation(owner: settings, page: page,
                availablePageIDs: availablePageIDs, breakpoint: breakpoint)
        return [".sf-page-navigation-\(surface.id) .sf-nav-menu { display:\(showsMenu ? "block" : "none"); }",
                ".sf-page-navigation-\(surface.id) .sf-nav-responsive { display:\(showsMenu ? "none" : "flex"); }"]
    }

    static func automaticMenuRules(_ page: DocumentPage, usesWrapper: Bool,
                                   availablePageIDs: Set<PageID>? = nil) -> [String] {
        var rules: [String] = []
        for owner in page.nodes {
            guard let row = CanonicalPageChrome.automaticMenuRow(owner: owner, page: page,
                breakpoint: .mobile, width: nil, availablePageIDs: availablePageIDs),
                CanonicalPageChrome.mobileOutputRoomFailure(owner: owner, page: page,
                    availablePageIDs: availablePageIDs) == nil else { continue }
            let container = usesWrapper ? "." + ConnectedFluidOutputPolicy.wrapperClass(row.contentID)
                : CanonicalCSSRule.selector(for: row.contentID)
            rules.append("\(container) { display:flex;flex-direction:row;gap:\(row.cssGap); }")
            if row.reservesMenu {
                rules.append(".sf-page-navigation-\(row.navigationID) { align-items:center; }")
                rules.append(".sf-page-navigation-\(row.navigationID) .sf-nav-menu { width:\(CanonicalPageChrome.menuControlWidth)px;max-width:100%; }")
                rules.append(".sf-page-navigation-\(row.navigationID) .sf-nav-menu summary { box-sizing:border-box;width:100%; }")
            }
            if !row.orderedIDs.contains(row.navigationID) {
                rules.append("\(CanonicalCSSRule.selector(for: row.navigationID)) { display:none; }")
            }
            for id in row.orderedIDs {
                let selector = CanonicalCSSRule.selector(for: id)
                let basis = id == row.navigationID ? row.navigationMinimum : id == row.titleID ? row.titleMaximum : row.fixedWidths[id] ?? 1
                let flex = id == row.navigationID ? "1 0 \(basis)px" : id == row.titleID ? "0 1 \(basis)px" : "0 0 \(basis)px"
                let minimum = id == row.titleID ? 1 : basis
                rules.append("\(selector) { position:relative;left:auto;top:auto;width:\(basis)px;flex:\(flex);min-width:\(minimum)px;max-width:\(id == row.navigationID ? "none" : "\(basis)px"); }")
            }
        }
        return rules.isEmpty ? [] : ["@media (width < 600px) { \(rules.joined(separator: "\n")) }"]
    }

    /// Presentation-only containing boxes keep padding outside authored paint
    /// bounds even when padding exceeds a tiny viewport. Their children use
    /// browser flex/grid/block flow, never preset-sampled top offsets.
    static func fluidFlowRules(_ page: DocumentPage, colorTokens: [LocalColorToken] = [],
                               availablePageIDs: Set<PageID>? = nil) -> [String] {
        guard ConnectedFluidOutputPolicy.needsAdapter(page), ConnectedFluidOutputPolicy.failures(page).isEmpty else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let wrappers = ConnectedFluidOutputPolicy.wrapperIDs(page)
        let automaticNavigationIDs = Set(page.nodes.filter { !CanonicalPageChrome.isCustom($0) }
            .compactMap { CanonicalPageChrome.reference(CanonicalPageChrome.navigationKey, on: $0) })
        func variable(_ id: NodeID, _ suffix: String) -> String { "--sf-\(id)-\(suffix)" }
        func value(_ id: NodeID, _ suffix: String) -> String { "var(\(variable(id, suffix)))" }
        func declaration(_ node: DocumentNode, _ suffix: String, _ scalar: ConnectedOutputLength) -> String { variable(node.id, suffix) + ":" + scalar.css }
        var output: [String] = []
        for breakpoint in ResponsiveBreakpoint.allCases {
            let width = CanonicalPageFlow.pageWidth(breakpoint, nil)
            let snapshot = ConnectedPageLayoutSnapshot(page: page, breakpoint: breakpoint, width: width,
                availablePageIDs: availablePageIDs)
            let scope = ResponsiveSizingLayout.scope(page: page, breakpoint: breakpoint, width: width)
            func mode(_ node: DocumentNode, _ dimension: SizingDimension) -> CanonicalSizingMode {
                CanonicalSizingConstraints.effectiveMode(dimension, node: node, breakpoint: breakpoint, width: width)
            }
            var rules = [".sf-page-\(page.id) { height:auto;min-height:100vh; }"]
            for link in page.nodes where CanonicalPageFlow.isNavigationLink(link) {
                rules.append(".sf-nav-link-\(link.id) { display:\(snapshot.visibleIDs.contains(link.id) ? "block" : "none"); }")
            }
            for node in page.canonicalDepthFirstNodes() where !CanonicalPageFlow.isNavigationLink(node) {
                let selector = CanonicalCSSRule.selector(for: node.id)
                guard snapshot.visibleIDs.contains(node.id), node.insertionGeometry != nil || page.rootNodeIDs.contains(node.id) else {
                    rules.append("\(selector)\(node.kind == .text ? "[data-siteforge-node]" : "") { display:none; }"); continue
                }
                let parent: DocumentNode? = { if case .node(let id) = node.parent { return byID[id] }; return nil }()
                let parentPolicy = parent.flatMap { snapshot.policies[$0.id] }
                let ownPolicy = snapshot.policies[node.id]
                let w = value(node.id, "w"), h = value(node.id, "h"), p = value(node.id, "p"), g = value(node.id, "g")
                var d = [declaration(node, "w", ConnectedFluidOutputPolicy.dimension(node, .width, breakpoint: breakpoint)),
                    declaration(node, "h", ConnectedFluidOutputPolicy.dimension(node, .height, breakpoint: breakpoint)),
                    "box-sizing:border-box", "margin:0", "padding:0", "min-width:1px", "min-height:1px", "max-width:none", "max-height:none",
                    "display:\(node.kind.isLinkControl ? "flex" : "block")", "position:relative", "left:auto", "top:auto", "right:auto", "bottom:auto", "width:\(w)", "height:\(h)", "flex:0 0 auto"]
                if let ownPolicy {
                    d += [declaration(node, "p", ConnectedFluidOutputPolicy.spacing(node, field: .padding, policy: ownPolicy, breakpoint: breakpoint)),
                        declaration(node, "g", ConnectedFluidOutputPolicy.spacing(node, field: .gap, policy: ownPolicy, breakpoint: breakpoint))]
                }
                if mode(node, .height) == .hug { d += ["height:auto"] }
                if mode(node, .width) == .fill { d += ["width:100%"] }
                let sizing = CanonicalSizingConstraints.resolved(for: node)
                if mode(node, .width) == .fill {
                    if let minimum = sizing.minWidth { d.append("min-width:\(minimum)px") }
                    if let maximum = sizing.maxWidth { d.append("max-width:\(maximum)px") }
                }
                if mode(node, .height) == .hug {
                    if let minimum = sizing.minHeight { d.append("min-height:\(minimum)px") }
                    if let maximum = sizing.maxHeight { d.append("max-height:\(maximum)px") }
                    if node.kind.isTextual { d += ["padding-inline:4px", "white-space:pre-wrap", "overflow-wrap:normal"] }
                    if node.kind == .button { d += ["padding-block:8px", "min-height:28px"] }
                }
                if let parent, let policy = parentPolicy {
                    let managedContent = CanonicalPageChrome.reference(CanonicalPageChrome.contentKey, on: parent) == node.id
                    let automaticNav = automaticNavigationIDs.contains(node.id)
                    if policy.naturalFlow {
                        if CanonicalPageFlow.role(node) != nil { d += ["width:100%", "min-width:1px", "max-width:none"] }
                        else {
                            let raw = ResponsiveGeometryResolver.geometry(for: node, breakpoint: breakpoint, viewportWidth: width)
                            d += ["position:absolute", "left:calc(\(raw?.origin.x ?? 0)px - \(value(parent.id, "p")))", "top:calc(\(raw?.origin.y ?? 0)px - \(value(parent.id, "p")))"]
                        }
                    } else if parent.kind == .grid {
                        if mode(node, .width) != .fill { d.append("min-width:0") }
                        if CanonicalSizingConstraints.dimensionResolution(.width, node: node, breakpoint: breakpoint, width: width).numericSource == nil { d.append("width:100%") }
                        if CanonicalSizingConstraints.dimensionResolution(.height, node: node, breakpoint: breakpoint, width: width).numericSource == nil { d.append("height:100%") }
                        d += ["align-self:start", "justify-self:start"]
                    } else if policy.axis == .horizontal {
                        d += ["flex:0 \(scope.affected.contains(parent.id) ? "0" : "1") \(w)", "max-height:100%"]
                        if policy.alignment == .stretch { d += ["height:100%"] }
                        if automaticNav || mode(node, .width) == .fill { d += ["width:auto", "flex:1 1 0px"] }
                    } else {
                        d += ["flex:0 \(scope.affected.contains(parent.id) ? "0" : "1") \(h)"]
                        if mode(node, .height) == .hug { d += ["flex:0 0 auto"] }
                        if CanonicalPageFlow.role(node) != nil || (policy.alignment == .stretch && !scope.affected.contains(parent.id)) || managedContent || mode(node, .width) == .fill {
                            d += ["width:100%"]
                        } else if !scope.affected.contains(parent.id) { d += ["width:min(\(w),100%)"] }
                    }
                    if managedContent { d += ["width:100%", "height:100%", "flex:0 0 auto"] }
                }
                if page.rootNodeIDs.contains(node.id) {
                    d += ["height:auto", "min-height:100vh", "width:\(node.insertionGeometry == nil ? "100%" : "min(100%,\(w))")", "display:flow-root"]
                }
                if wrappers.contains(node.id) { d.append("display:flow-root") }
                var values: [String: String] = [:], order: [String] = []
                for item in d {
                    guard let separator = item.firstIndex(of: ":") else { continue }
                    let key = String(item[..<separator])
                    if values[key] == nil { order.append(key) }
                    values[key] = String(item[item.index(after: separator)...])
                }
                if node.kind == .text, let height = values["height"] {
                    values["--sf-text-height"] = height; order.append("--sf-text-height")
                }
                rules.append("\(selector) { \(order.compactMap { key in values[key].map { key + ":" + $0 } }.joined(separator: ";")); }")
                if wrappers.contains(node.id), let policy = ownPolicy {
                    let relative = page.rootNodeIDs.contains(node.id) || policy.naturalFlow || mode(node, .height) == .hug
                    var box = ["box-sizing:border-box", "padding:0", "border:0", "min-width:0", "min-height:0", "left:\(p)",
                        "width:max(1px,calc(100% - 2 * \(p)))", "gap:\(g)", "align-content:start"]
                    box += relative ? ["position:relative", "top:auto", "height:auto", "margin-block:\(p)"]
                        : ["position:absolute", "top:\(p)", "height:max(1px,calc(100% - 2 * \(p)))", "margin:0"]
                    if policy.naturalFlow { box += ["display:flow-root"] }
                    else if node.kind == .grid {
                        box += ["display:grid", "grid-template-columns:repeat(\(policy.columns),calc(max(1px,calc(100% - \(policy.columns - 1) * \(g))) / \(policy.columns)))", "align-items:start"]
                        let ids = snapshot.layoutChildren[node.id] ?? []
                        let heights = ids.compactMap { byID[$0] }.map { ConnectedFluidOutputPolicy.dimension($0, .height, breakpoint: breakpoint).css }
                        var rows: [String] = []
                        for offset in stride(from: 0, to: heights.count, by: policy.columns) {
                            rows.append("max(1px," + heights[offset..<min(offset + policy.columns, heights.count)].joined(separator: ",") + ")")
                        }
                        if !rows.isEmpty { box.append("grid-template-rows:" + rows.joined(separator: " ")) }
                    } else {
                        let alignment = policy.alignment == .end ? "flex-end" : policy.alignment == .center ? "center" : policy.alignment == .stretch ? "stretch" : "flex-start"
                        box += ["display:flex", "flex-direction:\(policy.axis == .horizontal ? "row" : "column")", "align-items:\(alignment)"]
                    }
                    rules.append(".\(ConnectedFluidOutputPolicy.wrapperClass(node.id)) { \(box.joined(separator: ";")); }")
                }
                if let settings = CanonicalPageChrome.navigationSettings(for: node, page: page), snapshot.frames[node.id] != nil {
                    rules += navigationMenuRules(surface: node, settings: settings, page: page,
                        breakpoint: breakpoint, availablePageIDs: availablePageIDs ?? Set([page.id]))
                    let links = CanonicalPageChrome.links(owner: settings, page: page).filter { snapshot.visibleIDs.contains($0.id) }
                    guard !links.isEmpty else {
                        rules.append(".sf-page-navigation-\(node.id) { display:none; }")
                        continue
                    }
                    let gap = links.count > 1 ? "min(\(g),max(0px,calc((100% - \(links.count)px) / \(links.count - 1))))" : "0px"
                    let align = CanonicalPageChrome.navigationAlignment(surface: node, settings: settings)
                    let justify = align == "end" ? "flex-end" : align == "center" ? "center" : "flex-start"
                    let itemWidth = "calc((100% - \(links.count - 1) * \(gap)) / \(links.count))"
                    rules += [".sf-page-navigation-\(node.id) { display:\(breakpoint == .mobile ? "flex" : "block");justify-content:\(justify);left:0;top:0;width:100%;height:min(32px,100%); }"]
                    rules += [".sf-page-navigation-\(node.id) .sf-nav-inline { gap:\(gap);justify-content:\(justify); }"]
                    rules += [".sf-page-navigation-\(node.id) .sf-nav-inline a { width:\(align == "stretch" ? itemWidth : "min(160px,\(itemWidth))"); }"]
                    rules += [".sf-page-navigation-\(node.id) .sf-nav-menu { margin-left:\(align == "end" || align == "center" ? "auto" : "0");margin-right:\(align == "center" ? "auto" : "0"); }"]
                    if breakpoint == .mobile { rules += [".sf-page-navigation-\(node.id) .sf-nav-menu { flex:none;max-width:none;margin:0; }"] }
                    let panel = align == "end" ? "end" : align == "center" ? "center" : "start"
                    rules += [".sf-page-navigation-\(node.id) .sf-nav-menu { --sf-menu-panel-alignment:\(panel); }"]
                    let fallbackPanel = align == "end" ? "right:0;left:auto;" : align == "center" ? "left:50%;transform:translateX(-50%);" : "left:0;right:auto;"
                    rules += ["@supports not selector(details::details-content) { .sf-page-navigation-\(node.id) .sf-nav-menu[open] nav { \(fallbackPanel) } }"]
                    if let color = CanonicalPageChrome.navigationForeground(surface: node, page: page, tokens: colorTokens) {
                        rules += [".sf-page-navigation-\(node.id) .sf-nav-menu > summary { color:\(color.hexadecimalRGBA); }"]
                    }
                    if let color = CanonicalPageChrome.opaqueNavigationSurface(surface: node, page: page, tokens: colorTokens) {
                        rules += [".sf-page-navigation-\(node.id) .sf-nav-menu[open] nav { background:\(color.hexadecimalRGBA); }"]
                    }
                }
            }
            let joined = rules.joined(separator: "\n")
            output.append(breakpoint == .desktop ? joined : "@media \(breakpoint.cssMediaCondition ?? "all") { \(joined) }")
        }
        return output
    }

    /// Width is resolved before intrinsic height in both native and browser
    /// layout. Emit containing-block rules, not sampled preset-height literals.
    private static func automaticSizingDeclarations(node: DocumentNode, parent: DocumentNode?,
        snapshot: ConnectedPageLayoutSnapshot, breakpoint: ResponsiveBreakpoint,
        width: Double, localX: Double, localY: Double) -> [String] {
        func mode(_ node: DocumentNode, _ dimension: SizingDimension) -> CanonicalSizingMode {
            CanonicalSizingConstraints.effectiveMode(dimension, node: node, breakpoint: breakpoint, width: width)
        }
        let ownWidth = mode(node, .width), ownHeight = mode(node, .height)
        let sizing = CanonicalSizingConstraints.resolved(for: node)
        var result: [String] = []
        if ownWidth == .fill {
            let inset = parent.flatMap { parent in snapshot.policies[parent.id].map {
                ResponsiveSizingLayout.padding(parent, policy: $0, breakpoint: breakpoint, width: width)
            } } ?? 0
            result += ["width:max(1px,calc(100% - \(inset * 2)px))", "min-width:1px"]
            if let maximum = sizing.maxWidth { result += ["max-width:\(maximum)px"] }
        }
        if ownHeight == .hug { result += ["height:auto", "min-height:1px"] }
        if ownHeight == .fill { result += ["height:100%"] }
        if ownHeight == .hug, [.text, .link].contains(node.kind) {
            result += ["padding-inline:4px", "white-space:pre-wrap", "overflow-wrap:normal"]
        }
        if ownHeight == .hug, node.kind == .button { result += ["padding:8px 4px", "min-height:28px"] }
        if ownHeight == .hug, let policy = snapshot.policies[node.id] {
            if node.kind == .stack || node.kind == .section
                || (node.kind == .frame && DesignBoxStyleCommandRegistry.resolvedStyle(for: node)?.padding != nil) {
                let axis = node.kind == .stack && policy.axis == .horizontal ? "row" : "column"
                let align = policy.alignment == .center ? "center" : policy.alignment == .end ? "flex-end"
                    : policy.alignment == .stretch ? "stretch" : "flex-start"
                result += ["display:flex", "flex-direction:\(axis)", "gap:\(policy.gap)px",
                    "padding:\(policy.padding)px", "align-items:\(align)"]
            } else if node.kind == .grid {
                result += ["display:grid", "grid-template-columns:repeat(\(policy.columns),minmax(0,1fr))",
                    "gap:\(policy.gap)px", "padding:\(policy.padding)px", "align-items:start"]
            } else if node.kind == .frame, !policy.naturalFlow {
                // The overlay grid must hug its actual, width-resolved content.
                // Safari's default auto track can retain a larger intrinsic
                // measurement from before percentage-width text has wrapped.
                result += ["display:grid", "grid-template-columns:minmax(0,1fr)",
                    "grid-template-rows:max-content", "align-content:start"]
            }
        }
        if let parent, mode(parent, .height) == .hug, let policy = snapshot.policies[parent.id] {
            if ownHeight == .fill {
                // Fill-height backgrounds do not contribute to intrinsic height.
                let padding = ResponsiveSizingLayout.padding(parent, policy: policy, breakpoint: breakpoint, width: width)
                result += ["position:absolute", "top:\(padding)px", "bottom:\(padding)px", "height:auto"]
            } else if parent.kind == .stack || parent.kind == .section || parent.kind == .grid
                || (parent.kind == .frame && DesignBoxStyleCommandRegistry.resolvedStyle(for: parent)?.padding != nil) {
                // Each breakpoint must reset the entire flex basis. A Desktop
                // row's width basis otherwise cascades into Mobile's column
                // as a height, stretching a fixed-height Button unexpectedly.
                result += ["position:relative", "left:auto", "top:auto", "margin:0", "flex:0 0 auto"]
                if policy.axis == .horizontal, ownWidth != .fill, parent.kind != .grid {
                    let basis = ResponsiveGeometryResolver.geometry(for: node, breakpoint: breakpoint, viewportWidth: width)?.size.width ?? 1
                    result += ["flex:0 0 \(basis)px"]
                }
                if parent.kind == .grid,
                   CanonicalSizingConstraints.dimensionResolution(.width, node: node,
                    breakpoint: breakpoint, width: width).numericSource == nil { result += ["width:100%"] }
                else if ownWidth == .fill {
                    result += ["width:100%"]
                    if policy.axis == .horizontal { result += ["width:auto", "flex:1 1 0px"] }
                }
            } else if parent.kind == .frame, !policy.naturalFlow {
                result += ["position:relative", "grid-area:1 / 1", "top:auto", "left:auto",
                    "margin-top:\(max(0, localY))px", "align-self:start"]
                if ownWidth == .fill { result += ["justify-self:center"] }
                else { result += ["margin-left:\(max(0, localX))px"] }
            }
        }
        return result
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

    init(page: DocumentPage, breakpoint: ResponsiveBreakpoint, width: Double,
         availablePageIDs: Set<PageID>? = nil) {
        let resolved = page.resolvedStructuralGeometry(breakpoint: breakpoint, viewportWidth: width,
            availablePageIDs: availablePageIDs)
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

extension CanonicalPageChrome {
    /// A closed allocation intent for the existing automatic mobile row. It
    /// never rewrites source dimensions or samples a new breakpoint property.
    struct AutomaticMenuRow: Sendable {
        let contentID: NodeID
        let navigationID: NodeID
        let titleID: NodeID?
        let orderedIDs: [NodeID]
        let fixedWidths: [NodeID: Double]
        let titleMaximum: Double
        let preferredGap: Double
        let canReduceGap: Bool
        let padding: Double
        let alignment: ContainerLayoutAlignment
        let reservesMenu: Bool

        var navigationMinimum: Double {
            orderedIDs.contains(navigationID) ? (reservesMenu ? CanonicalPageChrome.menuControlWidth : 1) : 0
        }

        struct Allocation: Equatable, Sendable {
            let widths: [NodeID: Double]
            let gap: Double
        }
        func allocate(innerWidth: Double) -> Allocation? {
            guard innerWidth.isFinite, innerWidth > 0 else { return nil }
            let fixed = orderedIDs.reduce(0.0) { $0 + (fixedWidths[$1] ?? 0) }
            let minimumTitle = titleID == nil ? 0.0 : 1.0
            let gaps = Double(max(0, orderedIDs.count - 1))
            let minimum = fixed + navigationMinimum + minimumTitle
            let gap = canReduceGap && gaps > 0
                ? min(preferredGap, max(0, (innerWidth - minimum) / gaps)) : preferredGap
            guard innerWidth >= minimum + gaps * gap else { return nil }
            let titleWidth = titleID == nil ? 0 : min(titleMaximum,
                innerWidth - fixed - gaps * gap - navigationMinimum)
            var widths = fixedWidths
            if let titleID { widths[titleID] = titleWidth }
            if orderedIDs.contains(navigationID) {
                widths[navigationID] = innerWidth - fixed - gaps * gap - titleWidth
            }
            return .init(widths: widths, gap: gap)
        }

        /// Same flex priorities as allocate: fixed siblings, menu floor, then
        /// default title shrink. Percent gap resolves against the content box;
        /// the existing parent/wrapper applies inner spacing exactly once.
        var cssGap: String {
            let count = max(0, orderedIDs.count - 1)
            guard canReduceGap, count > 0 else { return "\(preferredGap)px" }
            let minimum = orderedIDs.reduce(0.0) { $0 + (fixedWidths[$1] ?? 0) }
                + navigationMinimum + (titleID == nil ? 0 : 1)
            return "min(\(preferredGap)px,max(0px,calc((100% - \(minimum)px) / \(count))))"
        }
    }

    static func automaticMenuRow(owner: DocumentNode, page: DocumentPage,
                                 breakpoint: ResponsiveBreakpoint, width: Double?,
                                 availablePageIDs: Set<PageID>? = nil) -> AutomaticMenuRow? {
        guard (width ?? CanonicalPageFlow.pageWidth(breakpoint, nil)) < 600,
              !isCustom(owner),
              let contentID = reference(contentKey, on: owner), let navigationID = reference(navigationKey, on: owner),
              let content = page.nodes.first(where: { $0.id == contentID }) else { return nil }
        let visible = page.effectiveVisibleNodeIDs(breakpoint: breakpoint)
        guard visible.contains(owner.id), visible.contains(contentID), visible.contains(navigationID) else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let links = Self.links(owner: owner, page: page).filter { visible.contains($0.id) }
        // Turning Menu off keeps ordinary inline layout. With no links there
        // is no navigation slot regardless of the retained Menu preference.
        guard links.isEmpty || owner.insertionProperty(CanonicalPageFlow.hamburgerKey)?.value == .boolean(true) else { return nil }
        let children = content.childIDs.filter { visible.contains($0) && ($0 != navigationID || !links.isEmpty) }
            .compactMap { byID[$0] }
        let reservesMenu = hasUsableNavigation(owner: owner, page: page,
            availablePageIDs: availablePageIDs ?? Set([page.id]), breakpoint: breakpoint)
        let policy = ResolvedContainerLayoutPolicy.resolve(content, children: children,
            breakpoint: breakpoint, viewportWidth: width)
        guard policy.axis == .horizontal,
              ResponsiveContainerLayoutResolver.value(for: .gap, node: content, breakpoint: breakpoint, viewportWidth: width)?.2 != .fluid,
              ResponsiveContainerLayoutResolver.value(for: .padding, node: content, breakpoint: breakpoint, viewportWidth: width)?.2 != .fluid else { return nil }
        // Larger/custom navigation typography retains its existing sizing,
        // rather than pretending the existing native control budget fits it.
        guard links.allSatisfy({ CanonicalFluidValueCodec.value(for: .fontSize, node: $0) == nil
            && CanonicalFluidValueCodec.value(for: .lineHeight, node: $0) == nil }) else { return nil }
        let fonts = links.compactMap { TypographyCommandRegistry.resolvedTypography(for: $0, viewportWidth: width) }
        guard fonts.allSatisfy({ $0.family == CanonicalTypography.defaultFamily
            && $0.size <= CanonicalTypography.defaultValue.size && $0.lineHeight <= 32 && $0.tracking <= 0 }) else { return nil }
        let titleID = reference(titleKey, on: owner).flatMap { visible.contains($0) ? $0 : nil }
        var fixed: [NodeID: Double] = [:], maximum = 0.0
        for child in children where child.id != navigationID {
            guard let resolved = ResponsiveGeometryResolver.value(for: .width, node: child,
                breakpoint: breakpoint, viewportWidth: width), resolved.2 != .fluid,
                CanonicalPositioning.resolve(child)?.mode == .static,
                !child.properties.contains(where: { $0.origin == .authored && $0.key.rawValue.hasPrefix(CanonicalSizingConstraints.prefix) }),
                CanonicalSizingConstraints.effectiveMode(.width, node: child, breakpoint: breakpoint, width: width) == .fixed else { return nil }
            if child.id == titleID {
                guard resolved.1 == .defaulted, resolved.2 == .baseDesktop,
                      !child.properties.contains(where: { $0.origin == .authored && $0.key.rawValue.hasPrefix(CanonicalSizingConstraints.prefix) }) else { return nil }
                maximum = resolved.0
            } else { fixed[child.id] = resolved.0 }
        }
        let gap = ResponsiveContainerLayoutResolver.value(for: .gap, node: content,
            breakpoint: breakpoint, viewportWidth: width)
        return .init(contentID: contentID, navigationID: navigationID, titleID: titleID,
            orderedIDs: children.map(\.id), fixedWidths: fixed, titleMaximum: maximum,
            preferredGap: policy.gap, canReduceGap: gap?.1 != .authored && gap?.2 == .baseDesktop,
            padding: policy.padding, alignment: policy.alignment, reservesMenu: reservesMenu)
    }

    static func resolvingAutomaticMenuRows(page: DocumentPage, frames: [NodeID: InsertionGeometry],
        breakpoint: ResponsiveBreakpoint, width: Double?, availablePageIDs: Set<PageID>? = nil) -> [NodeID: InsertionGeometry] {
        var result = frames
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let visible = page.effectiveVisibleNodeIDs(breakpoint: breakpoint)
        for owner in page.canonicalDepthFirstNodes() {
            guard let row = automaticMenuRow(owner: owner, page: page, breakpoint: breakpoint, width: width,
                availablePageIDs: availablePageIDs),
                  let box = result[row.contentID],
                  let allocation = row.allocate(innerWidth: max(1, box.size.width - 2 * row.padding)) else { continue }
            var x = box.origin.x + row.padding
            let height = max(1, box.size.height - 2 * row.padding)
            for id in row.orderedIDs {
                guard let old = result[id], let childWidth = allocation.widths[id] else { continue }
                let childHeight = row.alignment == .stretch ? height : min(old.size.height, height)
                let y = box.origin.y + row.padding + (row.alignment == .center ? (height - childHeight) / 2 : row.alignment == .end ? height - childHeight : 0)
                let dx = x - old.origin.x, dy = y - old.origin.y
                var pending = byID[id]?.childIDs ?? []
                while let descendant = pending.popLast() {
                    if let prior = result[descendant] {
                        result[descendant] = .init(origin: .init(x: prior.origin.x + dx, y: prior.origin.y + dy), size: prior.size)
                    }
                    pending += byID[descendant]?.childIDs ?? []
                }
                result[id] = .init(origin: .init(x: x, y: y), size: .init(width: childWidth, height: childHeight))
                if id == row.navigationID, let navigation = byID[id] {
                    let links = navigation.childIDs.filter(visible.contains)
                        .compactMap { byID[$0] }.filter(CanonicalPageFlow.isNavigationLink)
                    let layout = CanonicalPageFlow.navigationLayout(availableWidth: childWidth, count: links.count,
                        alignment: navigationAlignment(surface: navigation, settings: owner),
                        requestedGap: navigationGap(surface: navigation, settings: owner, breakpoint: breakpoint, width: width))
                    for (index, link) in links.enumerated() {
                        result[link.id] = .init(origin: .init(x: x + layout.offset + Double(index) * (layout.width + layout.gap), y: y),
                            size: .init(width: layout.width, height: min(32, childHeight)))
                    }
                }
                x += childWidth + allocation.gap
            }
        }
        return result
    }

    static func narrowMenuGuidance(owner: DocumentNode, page: DocumentPage,
                                   document: CanonicalDocument, width: Double,
                                   navigationBounds bounds: WorldRect) -> String? {
        guard width < 600, let navigationID = reference(navigationKey, on: owner),
              let surface = page.nodes.first(where: { $0.id == navigationID }),
              owner.insertionProperty(CanonicalPageFlow.hamburgerKey)?.value == .boolean(true) else { return nil }
        let visible = page.effectiveVisibleNodeIDs(breakpoint: .mobile)
        guard Self.links(owner: owner, page: page).contains(where: { link in
            guard visible.contains(link.id), let target = try? CanonicalLinkTarget.resolve(link), case .page(let id) = target else { return false }
            return document.websitePages.contains { $0.id == id }
        }) else { return nil }
        if bounds.size.width < menuControlWidth {
            return "Menu needs more room. Select Contents to reduce sizes or space between items. Your custom values have not changed."
        }
        let font = uniformNavigationTextSource(surface: surface, page: page, tokens: document.colorTokens)
            .flatMap { TypographyCommandRegistry.resolvedTypography(for: $0, viewportWidth: width) } ?? .defaultValue
        if font.lineHeight > bounds.size.height {
            return "Menu text is taller than its area. Adjust the Header/Footer height or navigation text size; your values are unchanged."
        }
        return nil
    }

    /// The requested 320-point phone is a compatibility probe, not a new
    /// breakpoint or an emitted frame. Do not export a known impossible row
    /// merely because the existing Mobile preset happens to be wider.
    static func mobileOutputRoomFailure(owner: DocumentNode, page: DocumentPage,
                                        availablePageIDs: Set<PageID>? = nil)
        -> ConnectedFluidOutputPolicy.Failure? {
        guard owner.insertionProperty(CanonicalPageFlow.hamburgerKey)?.value == .boolean(true),
              let navigationID = reference(navigationKey, on: owner) else { return nil }
        let visible = page.effectiveVisibleNodeIDs(breakpoint: .mobile)
        guard visible.contains(navigationID), hasUsableNavigation(owner: owner, page: page,
                availablePageIDs: availablePageIDs ?? Set([page.id]), breakpoint: .mobile),
              let navigation = page.resolvedStructuralGeometry(breakpoint: .mobile, viewportWidth: 320,
                availablePageIDs: availablePageIDs)[navigationID] else { return nil }
        guard navigation.size.width < menuControlWidth else { return nil }
        return ("page-flow-navigation-room", "This navigation row cannot keep its menu inside the requested 320-point phone layout.",
                "Select Header/Footer Contents and reduce custom sizes or spacing. Values remain unchanged; use native Preview until this row has enough room.")
    }
}

extension DocumentPage {
    var hasAutomaticSizing: Bool {
        nodes.contains { node in
            let sizing = CanonicalSizingConstraints.resolved(for: node)
            return sizing.widthMode != .fixed || sizing.heightMode != .fixed
        }
    }
    var usesConnectedOutput: Bool { hasAutomaticSizing || nodes.contains { CanonicalPageFlow.role($0) != nil } }
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
        viewportWidth: Double? = nil,
        availablePageIDs: Set<PageID>? = nil
    ) -> [NodeID: InsertionGeometry] {
        let fixed = fixedStructuralGeometry(breakpoint: breakpoint, viewportWidth: viewportWidth)
        let sized = ResponsiveSizingLayout.resolve(page: self, fixed: fixed, breakpoint: breakpoint, width: viewportWidth)
        return CanonicalPageChrome.resolvingAutomaticMenuRows(page: self, frames: sized,
            breakpoint: breakpoint, width: viewportWidth, availablePageIDs: availablePageIDs)
    }

    private func fixedStructuralGeometry(
        breakpoint: ResponsiveBreakpoint,
        viewportWidth: Double?
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
                        size: .init(
                            width: CanonicalSizingConstraints.dimensionResolution(.width, node: child,
                                breakpoint: breakpoint, width: viewportWidth).numericSource == nil ? cellWidth : geometry.size.width,
                            height: CanonicalSizingConstraints.dimensionResolution(.height, node: child,
                                breakpoint: breakpoint, width: viewportWidth).numericSource == nil ? rowHeights[row] : geometry.size.height)
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
                let alignment = CanonicalPageChrome.navigationAlignment(surface: parent, settings: settings)
                let navigationLayout = CanonicalPageFlow.navigationLayout(availableWidth: available, count: links.count, alignment: alignment,
                    requestedGap: CanonicalPageChrome.navigationGap(surface: parent, settings: settings,
                        breakpoint: breakpoint, width: viewportWidth))
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

/// The existing structural snapshot remains the only geometry source. Opt-in
/// sizing first resolves containing widths, then intrinsic heights bottom-up,
/// then positions top-down. Stored fixed frames and breakpoint intent are never
/// rewritten by measurement; old documents take the unchanged fixed path.
enum ResponsiveSizingLayout {
    struct Scope { let affected: Set<NodeID>; let descendants: Set<NodeID> }
    static func scope(page: DocumentPage, breakpoint: ResponsiveBreakpoint, width: Double?) -> Scope {
        let automatic = page.nodes.filter { CanonicalSizingConstraints.effectiveMode(.width, node: $0, breakpoint: breakpoint, width: width) != .fixed
            || CanonicalSizingConstraints.effectiveMode(.height, node: $0, breakpoint: breakpoint, width: width) != .fixed }
        guard !automatic.isEmpty else { return .init(affected: [], descendants: []) }
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        var affected = Set<NodeID>(), descendants = Set<NodeID>()
        for node in automatic {
            var pending = [node.id]
            while let id = pending.popLast() {
                guard descendants.insert(id).inserted else { continue }
                pending.append(contentsOf: byID[id]?.childIDs ?? [])
            }
            var current: DocumentNode? = node
            while let item = current, affected.insert(item.id).inserted {
                if case .node(let id) = item.parent { current = byID[id] } else { current = nil }
            }
        }
        affected.formUnion(descendants)
        return .init(affected: affected, descendants: descendants)
    }
    static func padding(_ parent: DocumentNode, policy: ResolvedContainerLayoutPolicy,
                        breakpoint: ResponsiveBreakpoint, width: Double?) -> Double {
        if parent.kind == .frame, DesignBoxStyleCommandRegistry.resolvedStyle(for: parent)?.padding == nil {
            return CanonicalPageFlow.role(parent) == nil ? 0
                : CanonicalPageFlow.padding(parent, breakpoint: breakpoint, width: width)
        }
        return policy.padding
    }
    static func resolve(page: DocumentPage, fixed: [NodeID: InsertionGeometry],
                        breakpoint: ResponsiveBreakpoint, width: Double?) -> [NodeID: InsertionGeometry] {
        func mode(_ node: DocumentNode, _ dimension: SizingDimension) -> CanonicalSizingMode {
            CanonicalSizingConstraints.effectiveMode(dimension, node: node, breakpoint: breakpoint, width: width)
        }
        let scope = Self.scope(page: page, breakpoint: breakpoint, width: width)
        guard !scope.affected.isEmpty else { return fixed }
        let ordered = page.canonicalDepthFirstNodes()
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let visible = page.effectiveVisibleNodeIDs(breakpoint: breakpoint)
        let affected = scope.affected, descendants = scope.descendants
        var result = fixed
        func children(_ parent: DocumentNode) -> [DocumentNode] {
            parent.childIDs.filter(visible.contains).compactMap { byID[$0] }.filter { result[$0.id] != nil }
        }
        func policy(_ parent: DocumentNode) -> ResolvedContainerLayoutPolicy {
            .resolve(parent, children: children(parent), breakpoint: breakpoint, viewportWidth: width)
        }
        func inset(_ parent: DocumentNode, _ policy: ResolvedContainerLayoutPolicy) -> Double {
            padding(parent, policy: policy, breakpoint: breakpoint, width: width)
        }
        func free(_ parent: DocumentNode, _ policy: ResolvedContainerLayoutPolicy) -> Bool {
            parent.kind == .frame && !policy.naturalFlow
                && DesignBoxStyleCommandRegistry.resolvedStyle(for: parent)?.padding == nil
        }
        func bounds(_ parent: DocumentNode) -> InsertionGeometry {
            result[parent.id] ?? .init(origin: .init(x: 0, y: 0),
                size: .init(width: CanonicalPageFlow.pageWidth(breakpoint, width), height: 900))
        }
        func constrained(_ value: Double, node: DocumentNode, dimension: SizingDimension) -> Double {
            let sizing = CanonicalSizingConstraints.resolved(for: node)
            let minimum = dimension == .width ? sizing.minWidth : sizing.minHeight
            let maximum = dimension == .width ? sizing.maxWidth : sizing.maxHeight
            return min(CanonicalSizingConstraints.maximum,
                max(max(1, minimum ?? 1), min(value, maximum ?? CanonicalSizingConstraints.maximum)))
        }
        func update(_ id: NodeID, x: Double? = nil, y: Double? = nil, w: Double? = nil, h: Double? = nil) {
            guard let old = result[id] else { return }
            result[id] = .init(origin: .init(x: x ?? old.origin.x, y: y ?? old.origin.y),
                size: .init(width: w ?? old.size.width, height: h ?? old.size.height))
        }
        for node in ordered where descendants.contains(node.id) {
            guard let raw = ResponsiveGeometryResolver.geometry(for: node, breakpoint: breakpoint, viewportWidth: width),
                  !CanonicalPageChrome.ownsFrame(of: node, in: page) else { continue }
            update(node.id, w: CanonicalPageFlow.role(node) == nil ? raw.size.width : nil, h: raw.size.height)
        }
        // Widths precede wrapping; Grid allocates its track before measuring
        // Text. Fill siblings in a horizontal Stack share the remaining width.
        for parent in ordered where affected.contains(parent.id) {
            let items = children(parent), layout = policy(parent), padding = inset(parent, layout)
            let available = max(1, bounds(parent).size.width - padding * 2)
            let fills = items.filter { mode($0, .width) == .fill }
            let fixedWidth = items.filter { mode($0, .width) != .fill }.reduce(0.0) { $0 + (result[$1.id]?.size.width ?? 1) }
            let share = max(1, (available - fixedWidth - Double(max(0, items.count - 1)) * layout.gap) / Double(max(1, fills.count)))
            for child in items {
                if parent.kind == .grid {
                    let cell = max(1, (available - Double(layout.columns - 1) * layout.gap) / Double(layout.columns))
                    // Tracks own default placement, not explicit numeric intent.
                    // Preserve the winning breakpoint/fluid width before text
                    // measurement and use the same condition in CSS projection.
                    if CanonicalSizingConstraints.dimensionResolution(.width, node: child,
                        breakpoint: breakpoint, width: width).numericSource == nil {
                        update(child.id, w: constrained(cell, node: child, dimension: .width))
                    }
                } else if mode(child, .width) == .fill {
                    let value = parent.kind == .stack && layout.axis == .horizontal ? share : available
                    update(child.id, w: constrained(value, node: child, dimension: .width))
                }
            }
        }
        for node in ordered.reversed() where mode(node, .height) == .hug {
            guard let own = result[node.id] else { continue }
            let layout = policy(node), padding = inset(node, layout)
            let items = children(node).filter { mode($0, .height) != .fill }
            let height: Double
            if [.text, .button, .link].contains(node.kind) {
                let typography = TypographyCommandRegistry.resolvedTypography(for: node, viewportWidth: width) ?? .defaultValue
                let text = node.kind.isLinkControl ? node.controlLabel : node.insertionStringProperty("content.text") ?? ""
                height = ResponsiveTextMetrics.height(text: text, width: own.size.width, typography: typography)
                    + (node.kind == .button ? 16 : 0)
            } else if free(node, layout) {
                height = items.reduce(padding, { max($0, (fixed[$1.id]?.origin.y ?? own.origin.y)
                    - (fixed[node.id]?.origin.y ?? own.origin.y) + (result[$1.id]?.size.height ?? 0)) }) + padding
            } else if node.kind == .grid {
                var rows: [Double] = []
                for (index, child) in items.enumerated() {
                    if index % layout.columns == 0 { rows.append(0) }
                    rows[rows.count - 1] = max(rows[rows.count - 1], result[child.id]?.size.height ?? 1)
                }
                height = rows.reduce(0, +) + Double(max(0, rows.count - 1)) * layout.gap + padding * 2
            } else if node.kind == .stack && layout.axis == .horizontal {
                height = (items.compactMap { result[$0.id]?.size.height }.max() ?? 0) + padding * 2
            } else {
                height = items.reduce(0) { $0 + (result[$1.id]?.size.height ?? 1) }
                    + Double(max(0, items.count - 1)) * layout.gap + padding * 2
            }
            update(node.id, h: constrained(node.kind == .button ? max(28, height) : height, node: node, dimension: .height))
        }
        for parent in ordered {
            let items = children(parent), layout = policy(parent), padding = inset(parent, layout), own = bounds(parent)
            let oldOrigin = fixed[parent.id]?.origin ?? own.origin
            let delta = LayoutPoint(x: own.origin.x - oldOrigin.x, y: own.origin.y - oldOrigin.y)
            guard affected.contains(parent.id) else {
                for child in items {
                    if let old = fixed[child.id] { update(child.id, x: old.origin.x + delta.x, y: old.origin.y + delta.y) }
                }
                continue
            }
            if layout.naturalFlow {
                var y = own.origin.y + padding
                let flow = CanonicalPageFlow.ordered(items)
                for child in flow {
                    update(child.id, x: own.origin.x + padding, y: y,
                        w: max(1, own.size.width - padding * 2))
                    y += result[child.id]?.size.height ?? 1
                }
                continue
            }
            let availableWidth = max(1, own.size.width - padding * 2)
            let availableHeight = max(1, own.size.height - padding * 2)
            if free(parent, layout) {
                for child in items {
                    guard let value = result[child.id], let old = fixed[child.id] else { continue }
                    update(child.id,
                        x: mode(child, .width) == .fill ? own.origin.x + padding + (availableWidth - value.size.width) / 2 : old.origin.x + delta.x,
                        y: mode(child, .height) == .fill ? own.origin.y + padding : old.origin.y + delta.y,
                        h: mode(child, .height) == .fill ? constrained(availableHeight, node: child, dimension: .height) : nil)
                }
            } else if parent.kind == .grid {
                let cell = max(1, (availableWidth - Double(layout.columns - 1) * layout.gap) / Double(layout.columns))
                var y = own.origin.y + padding, rowHeight = 0.0
                for (index, child) in items.enumerated() {
                    if index > 0, index % layout.columns == 0 { y += rowHeight + layout.gap; rowHeight = 0 }
                    update(child.id, x: own.origin.x + padding + Double(index % layout.columns) * (cell + layout.gap), y: y)
                    rowHeight = max(rowHeight, result[child.id]?.size.height ?? 1)
                }
            } else {
                var cursor = layout.axis == .vertical ? own.origin.y + padding : own.origin.x + padding
                let filled = items.filter { mode($0, .height) == .fill }
                let fixedHeight = items.filter { mode($0, .height) != .fill }.reduce(0.0) { $0 + (result[$1.id]?.size.height ?? 1) }
                let share = max(1, (availableHeight - fixedHeight - Double(max(0, items.count - 1)) * layout.gap) / Double(max(1, filled.count)))
                for child in items {
                    guard let value = result[child.id] else { continue }
                    let height = mode(child, .height) == .fill ? constrained(layout.axis == .vertical ? share : availableHeight, node: child, dimension: .height) : value.size.height
                    if layout.axis == .vertical {
                        let x = own.origin.x + padding + (layout.alignment == .center ? (availableWidth - value.size.width) / 2 : layout.alignment == .end ? availableWidth - value.size.width : 0)
                        update(child.id, x: x, y: cursor, h: height)
                        cursor += height + layout.gap
                    } else {
                        let y = own.origin.y + padding + (layout.alignment == .center ? (availableHeight - height) / 2 : layout.alignment == .end ? availableHeight - height : 0)
                        update(child.id, x: cursor, y: y, h: layout.alignment == .stretch ? availableHeight : height)
                        cursor += value.size.width + layout.gap
                    }
                }
            }
        }
        return result
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
