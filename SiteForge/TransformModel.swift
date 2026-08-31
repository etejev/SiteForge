import CryptoKit
import Foundation

// SF-0403-001...008 — bounded deterministic move/resize geometry transforms.

// SF-0508-001...008 — bounded solid fill and opacity authoring.  RGBA is
// deliberately stored as four finite canonical numeric properties rather than
// a presentation string, so locale/display color notation never becomes part
// of the document format.
struct CanonicalSolidColor: Equatable, Sendable {
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

// SF-0506-001...008 — bounded canonical border, uniform radius, and one
// production shadow. Presentation drafts never enter this representation.
enum CanonicalBorderStyle: String, CaseIterable, Sendable { case solid, dashed, dotted }

struct CanonicalBorder: Equatable, Sendable {
    let color: CanonicalSolidColor
    let width: Double
    let style: CanonicalBorderStyle
    var isValid: Bool { color.isValid && width.isFinite && width > 0 && width <= 100 }
}

struct CanonicalShadow: Equatable, Sendable {
    let color: CanonicalSolidColor
    let offsetX: Double
    let offsetY: Double
    let blur: Double
    let spread: Double
    var isValid: Bool {
        color.isValid && [offsetX, offsetY, blur, spread].allSatisfy(\.isFinite)
            && (-10_000...10_000).contains(offsetX)
            && (-10_000...10_000).contains(offsetY)
            && (0...1_000).contains(blur)
            && (-1_000...1_000).contains(spread)
    }
}

struct CanonicalBoxStyle: Equatable, Sendable {
    let border: CanonicalBorder?
    let cornerRadius: Double?
    let shadow: CanonicalShadow?
    var isValid: Bool {
        (border?.isValid ?? true)
            && (cornerRadius.map { $0.isFinite && (0...10_000).contains($0) } ?? true)
            && (shadow?.isValid ?? true)
    }
}

enum DesignBoxStyleValue: Equatable, Sendable {
    case unavailable(String)
    case single(CanonicalBoxStyle, PropertyOrigin)
    case mixed(applicableCount: Int, skippedCount: Int)
}

enum DesignBoxStyleEdit: Sendable {
    case border(CanonicalBorder?)
    case cornerRadius(Double?)
    case shadow(CanonicalShadow?)
}

struct DesignBoxStyleCommand: Sendable {
    let identity: DesignInspectorOperationIdentity
    let orderedNodeIDs: [NodeID]
    let edit: DesignBoxStyleEdit
    let provenance: DesignInspectorProvenance
    let cancelled: Bool
}

enum DesignBoxStyleError: Error, LocalizedError, Equatable, Sendable {
    case stale, cancelled, invalidValue, unavailable(String), noApplicableTargets, noChanges
    var errorDescription: String? {
        switch self {
        case .stale: "The border, radius, or shadow edit is stale; committed appearance is unchanged."
        case .cancelled: "The appearance draft was cancelled; committed appearance is unchanged."
        case .invalidValue: "Enter a finite border, radius, or shadow value within the supported range."
        case .unavailable(let reason): reason
        case .noApplicableTargets: "The selection has no object that supports border, radius, or shadow."
        case .noChanges: "The appearance already has that value."
        }
    }
}

struct DesignBoxStyleCommandRegistry: Sendable {
    static let requirementIDs: Set<String> = Set((1...8).map { String(format: "SF-0506-%03d", $0) })
    static let applicableKinds: Set<NodeKind> = [.frame, .section, .stack, .grid]
    static let namespace = "style.box.v1."

    static func resolvedStyle(for node: DocumentNode) -> CanonicalBoxStyle? {
        guard applicableKinds.contains(node.kind) else { return nil }
        func number(_ key: String) -> Double? { node.insertionNumberProperty(namespace + key) }
        func color(_ prefix: String) -> CanonicalSolidColor? {
            guard let r = number(prefix + ".red"), let g = number(prefix + ".green"),
                  let b = number(prefix + ".blue"), let a = number(prefix + ".alpha") else { return nil }
            let value = CanonicalSolidColor(red: r, green: g, blue: b, alpha: a)
            return value.isValid ? value : nil
        }
        let border: CanonicalBorder? = {
            guard let width = number("border.width"), width > 0,
                  let value = color("border.color"),
                  let raw = node.insertionStringProperty(namespace + "border.style"),
                  let style = CanonicalBorderStyle(rawValue: raw) else { return nil }
            let result = CanonicalBorder(color: value, width: width, style: style)
            return result.isValid ? result : nil
        }()
        let radius = number("radius.uniform").flatMap { $0.isFinite && (0...10_000).contains($0) ? $0 : nil }
        let shadow: CanonicalShadow? = {
            guard let value = color("shadow.color"), let x = number("shadow.offsetX"),
                  let y = number("shadow.offsetY"), let blur = number("shadow.blur"),
                  let spread = number("shadow.spread") else { return nil }
            let result = CanonicalShadow(color: value, offsetX: x, offsetY: y, blur: blur, spread: spread)
            return result.isValid ? result : nil
        }()
        return CanonicalBoxStyle(border: border, cornerRadius: radius, shadow: shadow)
    }

    static func selectionValue(nodes: [DocumentNode]) -> DesignBoxStyleValue {
        guard !nodes.isEmpty else { return .unavailable("Select a Frame, Section, Stack, or Grid to edit border, radius, and shadow.") }
        let applicable = nodes.filter { applicableKinds.contains($0.kind) }
        guard !applicable.isEmpty else { return .unavailable("The selected objects do not support box appearance.") }
        let values = applicable.compactMap(resolvedStyle)
        guard let first = values.first, values.dropFirst().allSatisfy({ $0 == first }) else {
            return .mixed(applicableCount: applicable.count, skippedCount: nodes.count - applicable.count)
        }
        let origin = applicable.flatMap(\.properties).contains { $0.key.rawValue.hasPrefix(namespace) } ? PropertyOrigin.authored : .defaulted
        return .single(first, origin)
    }

    func prepare(_ command: DesignBoxStyleCommand, in document: CanonicalDocument, context: TransformValidationContext) throws -> PreparedDesignInspectorEdit {
        guard !command.cancelled else { throw DesignBoxStyleError.cancelled }
        guard context.isLifecycleAvailable else { throw DesignBoxStyleError.unavailable(context.lifecycleDisabledReason ?? "Appearance editing is unavailable.") }
        guard command.identity.documentID == document.id, command.identity.revision == document.revision,
              command.identity.pageID == context.activePageID, command.identity.sceneID == context.currentSceneID,
              command.identity.rendererGeneration == context.rendererGeneration,
              command.orderedNodeIDs == context.selectedNodeIDs, !command.orderedNodeIDs.isEmpty else { throw DesignBoxStyleError.stale }
        guard Set(command.orderedNodeIDs).count == command.orderedNodeIDs.count,
              let page = document.pages.first(where: { $0.id == command.identity.pageID }) else { throw DesignBoxStyleError.stale }
        var applicable: [NodeID] = [], skipped: [NodeID] = [], reasons: [NodeID: String] = [:], changes: [DocumentCommand] = []
        for id in command.orderedNodeIDs {
            guard let node = page.nodes.first(where: { $0.id == id }) else { throw DesignBoxStyleError.stale }
            guard context.availableNodeIDs.contains(id), !node.selectionBooleanProperty("hidden"), !node.selectionBooleanProperty("locked") else {
                throw DesignBoxStyleError.unavailable("A selected object is unavailable, hidden, or locked.")
            }
            guard Self.applicableKinds.contains(node.kind), var style = Self.resolvedStyle(for: node) else {
                skipped.append(id); reasons[id] = "This object kind does not support box appearance."; continue
            }
            switch command.edit {
            case .border(let value):
                if let value, !value.isValid { throw DesignBoxStyleError.invalidValue }
                style = .init(border: value, cornerRadius: style.cornerRadius, shadow: style.shadow)
            case .cornerRadius(let value):
                if let value, (!value.isFinite || !(0...10_000).contains(value)) { throw DesignBoxStyleError.invalidValue }
                style = .init(border: style.border, cornerRadius: value, shadow: style.shadow)
            case .shadow(let value):
                if let value, !value.isValid { throw DesignBoxStyleError.invalidValue }
                style = .init(border: style.border, cornerRadius: style.cornerRadius, shadow: value)
            }
            guard style.isValid else { throw DesignBoxStyleError.invalidValue }
            applicable.append(id)
            let desired = Self.propertyValues(for: style)
            let owned = node.properties.filter { $0.key.rawValue.hasPrefix(Self.namespace) }
            let byKey = Dictionary(uniqueKeysWithValues: owned.map { ($0.key.rawValue, $0) })
            for key in desired.keys.sorted() {
                guard let value = desired[key] else { continue }
                let old = byKey[key]
                if old?.value != value || old?.origin != .authored {
                    changes.append(.setProperty(.init(pageID: page.id, nodeID: id, property: .init(id: old?.id ?? PropertyID(), key: .init(rawValue: key), value: value, origin: .authored))))
                }
            }
            for old in owned where desired[old.key.rawValue] == nil {
                changes.append(.removeProperty(.init(pageID: page.id, nodeID: id, propertyID: old.id)))
            }
        }
        guard !applicable.isEmpty else { throw DesignBoxStyleError.noApplicableTargets }
        guard !changes.isEmpty else { throw DesignBoxStyleError.noChanges }
        let batch: DocumentCommand = .batch(changes)
        guard CommandRegistry().availability(for: batch, in: document).isEnabled else { throw DesignBoxStyleError.stale }
        return .init(applicableNodeIDs: applicable, skippedNodeIDs: skipped, skippedReasons: reasons, documentCommand: batch)
    }

    static func propertyValues(for style: CanonicalBoxStyle) -> [String: PropertyValue] {
        var result: [String: PropertyValue] = [:]
        if let border = style.border {
            result[namespace + "border.width"] = .number(border.width)
            result[namespace + "border.style"] = .string(border.style.rawValue)
            set(border.color, prefix: namespace + "border.color", into: &result)
        }
        if let radius = style.cornerRadius { result[namespace + "radius.uniform"] = .number(radius) }
        if let shadow = style.shadow {
            result[namespace + "shadow.offsetX"] = .number(shadow.offsetX)
            result[namespace + "shadow.offsetY"] = .number(shadow.offsetY)
            result[namespace + "shadow.blur"] = .number(shadow.blur)
            result[namespace + "shadow.spread"] = .number(shadow.spread)
            set(shadow.color, prefix: namespace + "shadow.color", into: &result)
        }
        return result
    }

    private static func set(_ color: CanonicalSolidColor, prefix: String, into values: inout [String: PropertyValue]) {
        values[prefix + ".red"] = .number(color.red); values[prefix + ".green"] = .number(color.green)
        values[prefix + ".blue"] = .number(color.blue); values[prefix + ".alpha"] = .number(color.alpha)
    }
}

// SF-0507-001...008 — bounded canonical plain-text typography. Installed
// font availability is deliberately not serialized: the authored family is
// stable intent, while AppKit resolves that intent (or a deterministic system
// fallback) into an immutable renderer/editor snapshot.
enum TypographyInspectorValue: Equatable, Sendable {
    case unavailable(String)
    case single(CanonicalTypography, PropertyOrigin)
    case mixed(applicableCount: Int, skippedCount: Int)
}

enum TypographyEdit: Sendable {
    case reset
    case family(String?)
    case weight(CanonicalFontWeight?)
    case size(Double?)
    case lineHeight(Double?)
    case tracking(Double?)
    case alignment(CanonicalTextAlignment?)
}

struct TypographyCommand: Sendable {
    let identity: DesignInspectorOperationIdentity
    let orderedNodeIDs: [NodeID]
    let edit: TypographyEdit
    let provenance: DesignInspectorProvenance
    let cancelled: Bool
}

enum TypographyCommandError: Error, LocalizedError, Equatable, Sendable {
    case stale, cancelled, invalidValue, unavailable(String), noApplicableTargets, noChanges
    var errorDescription: String? {
        switch self {
        case .stale: "The typography edit is stale; committed text style is unchanged."
        case .cancelled: "The typography draft was cancelled; committed text style is unchanged."
        case .invalidValue: "Enter a valid font family and finite typography values within the supported ranges."
        case .unavailable(let reason): reason
        case .noApplicableTargets: "The selection has no plain Text object that supports typography."
        case .noChanges: "Typography already has that value."
        }
    }
}

struct TypographyCommandRegistry: Sendable {
    static let requirementIDs = Set((1...8).map { String(format: "SF-0507-%03d", $0) })
    static let namespace = CanonicalTypography.namespace

    static func resolvedTypography(for node: DocumentNode) -> CanonicalTypography? {
        guard node.kind == .text else { return nil }
        func string(_ suffix: String) -> String? { node.insertionStringProperty(namespace + suffix) }
        func number(_ suffix: String) -> Double? { node.insertionNumberProperty(namespace + suffix) }
        let fallback = CanonicalTypography.defaultValue
        let value = CanonicalTypography(
            family: string("family") ?? fallback.family,
            weight: string("weight").flatMap(CanonicalFontWeight.init(rawValue:)) ?? fallback.weight,
            size: number("size") ?? fallback.size,
            lineHeight: number("lineHeight") ?? fallback.lineHeight,
            tracking: number("tracking") ?? fallback.tracking,
            alignment: string("alignment").flatMap(CanonicalTextAlignment.init(rawValue:)) ?? fallback.alignment
        )
        return value.isValid ? value : nil
    }

    static func selectionValue(nodes: [DocumentNode]) -> TypographyInspectorValue {
        guard !nodes.isEmpty else { return .unavailable("Select plain Text to edit typography.") }
        let applicable = nodes.filter { $0.kind == .text }
        guard !applicable.isEmpty else { return .unavailable("Typography applies only to plain Text in this milestone.") }
        let values = applicable.compactMap(resolvedTypography)
        guard values.count == applicable.count, let first = values.first,
              values.dropFirst().allSatisfy({ $0 == first }) else {
            return .mixed(applicableCount: applicable.count, skippedCount: nodes.count - applicable.count)
        }
        let origin: PropertyOrigin = applicable.flatMap(\.properties).contains { $0.key.rawValue.hasPrefix(namespace) && $0.origin == .authored } ? .authored : .defaulted
        return .single(first, origin)
    }

    func prepare(_ command: TypographyCommand, in document: CanonicalDocument, context: TransformValidationContext) throws -> PreparedDesignInspectorEdit {
        guard !command.cancelled else { throw TypographyCommandError.cancelled }
        guard context.isLifecycleAvailable else { throw TypographyCommandError.unavailable(context.lifecycleDisabledReason ?? "Typography editing is unavailable.") }
        guard command.identity.documentID == document.id,
              command.identity.pageID == context.activePageID,
              command.identity.revision == document.revision,
              command.identity.sceneID == context.currentSceneID,
              command.identity.rendererGeneration == context.rendererGeneration,
              command.orderedNodeIDs == context.selectedNodeIDs,
              !command.orderedNodeIDs.isEmpty,
              Set(command.orderedNodeIDs).count == command.orderedNodeIDs.count,
              let page = document.pages.first(where: { $0.id == command.identity.pageID }) else {
            throw TypographyCommandError.stale
        }
        var applicable: [NodeID] = [], skipped: [NodeID] = [], reasons: [NodeID: String] = [:]
        var changes: [DocumentCommand] = []
        for id in command.orderedNodeIDs {
            guard let node = page.nodes.first(where: { $0.id == id }) else { throw TypographyCommandError.stale }
            guard context.availableNodeIDs.contains(id), !node.selectionBooleanProperty("hidden"), !node.selectionBooleanProperty("locked") else {
                throw TypographyCommandError.unavailable("A selected object is unavailable, hidden, or locked.")
            }
            guard node.kind == .text, var style = Self.resolvedTypography(for: node) else {
                skipped.append(id); reasons[id] = "This object kind does not support typography."; continue
            }
            if case .reset = command.edit {
                applicable.append(id)
                changes.append(contentsOf: node.properties
                    .filter { $0.key.rawValue.hasPrefix(Self.namespace) }
                    .map { .removeProperty(.init(pageID: page.id, nodeID: id, propertyID: $0.id)) })
                continue
            }
            let key: String
            let value: PropertyValue?
            switch command.edit {
            case .reset:
                preconditionFailure("Reset is handled before scalar typography edits.")
            case .family(let next):
                key = "family"; value = next.map(PropertyValue.string)
                if let next { style = .init(family: next, weight: style.weight, size: style.size, lineHeight: style.lineHeight, tracking: style.tracking, alignment: style.alignment) }
            case .weight(let next):
                key = "weight"; value = next.map { .string($0.rawValue) }
                if let next { style = .init(family: style.family, weight: next, size: style.size, lineHeight: style.lineHeight, tracking: style.tracking, alignment: style.alignment) }
            case .size(let next):
                key = "size"; value = next.map(PropertyValue.number)
                if let next { style = .init(family: style.family, weight: style.weight, size: next, lineHeight: style.lineHeight, tracking: style.tracking, alignment: style.alignment) }
            case .lineHeight(let next):
                key = "lineHeight"; value = next.map(PropertyValue.number)
                if let next { style = .init(family: style.family, weight: style.weight, size: style.size, lineHeight: next, tracking: style.tracking, alignment: style.alignment) }
            case .tracking(let next):
                key = "tracking"; value = next.map(PropertyValue.number)
                if let next { style = .init(family: style.family, weight: style.weight, size: style.size, lineHeight: style.lineHeight, tracking: next, alignment: style.alignment) }
            case .alignment(let next):
                key = "alignment"; value = next.map { .string($0.rawValue) }
                if let next { style = .init(family: style.family, weight: style.weight, size: style.size, lineHeight: style.lineHeight, tracking: style.tracking, alignment: next) }
            }
            guard style.isValid else { throw TypographyCommandError.invalidValue }
            applicable.append(id)
            let fullKey = Self.namespace + key
            let old = node.properties.first { $0.key.rawValue == fullKey }
            if let value {
                if old?.value != value || old?.origin != .authored {
                    changes.append(.setProperty(.init(pageID: page.id, nodeID: id, property: .init(id: old?.id ?? PropertyID(), key: .init(rawValue: fullKey), value: value, origin: .authored))))
                }
            } else if let old {
                changes.append(.removeProperty(.init(pageID: page.id, nodeID: id, propertyID: old.id)))
            }
        }
        guard !applicable.isEmpty else { throw TypographyCommandError.noApplicableTargets }
        guard !changes.isEmpty else { throw TypographyCommandError.noChanges }
        let batch: DocumentCommand = .batch(changes)
        guard CommandRegistry().availability(for: batch, in: document).isEnabled else { throw TypographyCommandError.stale }
        return .init(applicableNodeIDs: applicable, skippedNodeIDs: skipped, skippedReasons: reasons, documentCommand: batch)
    }
}

// SF-0508-001...008 — canonical ordered fill-layer foundation. Layer and
// stop identities belong to the document representation; previews and picker
// drafts deliberately do not. The property codec/registry adoption follows in
// this bounded slice, so these value types keep validation deterministic and
// independent of SwiftUI/AppKit presentation.
enum FillLayerIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "fill-layer"
}
typealias FillLayerID = StableIdentifier<FillLayerIdentifierDomain>

enum GradientStopIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "gradient-stop"
}
typealias GradientStopID = StableIdentifier<GradientStopIdentifierDomain>

struct CanonicalGradientStop: Equatable, Sendable {
    let id: GradientStopID
    let position: Double
    let color: CanonicalSolidColor

    var isValid: Bool { position.isFinite && (0...1).contains(position) && color.isValid }
}

enum CanonicalFillLayerKind: String, Equatable, Sendable {
    case solid
    case linearGradient
}

struct CanonicalFillLayer: Equatable, Sendable {
    let id: FillLayerID
    let kind: CanonicalFillLayerKind
    let isEnabled: Bool
    let solidColor: CanonicalSolidColor?
    let angleDegrees: Double?
    let stops: [CanonicalGradientStop]

    static func solid(id: FillLayerID = FillLayerID(), color: CanonicalSolidColor, isEnabled: Bool = true) -> CanonicalFillLayer {
        CanonicalFillLayer(id: id, kind: .solid, isEnabled: isEnabled, solidColor: color, angleDegrees: nil, stops: [])
    }

    static func linearGradient(id: FillLayerID = FillLayerID(), angleDegrees: Double = 180, stops: [CanonicalGradientStop], isEnabled: Bool = true) -> CanonicalFillLayer {
        CanonicalFillLayer(id: id, kind: .linearGradient, isEnabled: isEnabled, solidColor: nil, angleDegrees: angleDegrees, stops: stops)
    }

    var isValid: Bool {
        switch kind {
        case .solid:
            return solidColor?.isValid == true && angleDegrees == nil && stops.isEmpty
        case .linearGradient:
            guard solidColor == nil, let angleDegrees, angleDegrees.isFinite,
                  stops.count >= 2, Set(stops.map(\.id)).count == stops.count,
                  stops.allSatisfy(\.isValid) else { return false }
            // Stop list order is a stable authored/UI ordering. Position is a
            // separate normalized interpolation coordinate; the renderer will
            // sort a local immutable copy by position (then stable list index)
            // so a requested reorder never becomes an impossible operation.
            return true
        }
    }

    /// Canonicalized angle keeps equality, history, and renderer snapshots
    /// stable while accepting any finite user-facing turn count.
    var normalizedAngleDegrees: Double? {
        guard let angleDegrees else { return nil }
        let value = angleDegrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}

enum CanonicalFillLayerDecodingResult: Equatable, Sendable {
    case absent
    case layers([CanonicalFillLayer])
}

enum CanonicalFillLayerDecodingError: Error, Equatable, Sendable {
    case unsupportedNodeKind
    case duplicateProperty
    case missingOrder
    case invalidOrder
    case duplicateLayerID
    case invalidLayer
    case invalidStopOrder
    case duplicateStopID
    case invalidStop
    case orphanedProperty
}

/// Versioned property codec for the v5 layer model. The ordered identity lists
/// are canonical identifiers (not presentation color strings); all visual
/// values remain typed finite numbers. Legacy v4 solid properties are read
/// only as a deterministic migration input and are never consulted once a v5
/// order property exists.
enum CanonicalFillLayerCodec {
    static let namespaceRoot = "style.fill.layers.v1"
    static let orderKey = "style.fill.layers.v1.order"
    private static let supportedKinds: Set<NodeKind> = [.frame, .section, .stack, .grid]

    static func layers(for node: DocumentNode) -> [CanonicalFillLayer]? {
        do {
            switch try decodeLayers(for: node) {
            case .absent: return nil
            case .layers(let layers): return layers
            }
        } catch {
            // A malformed candidate never revives legacy values as a second
            // visual authority. Canonical document validation rejects this
            // state before adoption; this fallback keeps projections safe for
            // transient test/debug values that have not crossed that gate.
            return []
        }
    }

    /// Strictly decodes the owned namespace. Absence is distinct from an
    /// explicitly authored empty list, while every malformed or unreachable
    /// property is rejected instead of being presented as "no fill".
    static func decodeLayers(for node: DocumentNode) throws -> CanonicalFillLayerDecodingResult {
        let namespaceProperties = node.properties.filter { ownsNamespace($0.key.rawValue) }
        guard !namespaceProperties.isEmpty else { return .absent }
        guard supportedKinds.contains(node.kind) else {
            throw CanonicalFillLayerDecodingError.unsupportedNodeKind
        }

        let keys = namespaceProperties.map(\.key.rawValue)
        guard Set(keys).count == keys.count else {
            throw CanonicalFillLayerDecodingError.duplicateProperty
        }
        let properties = Dictionary(uniqueKeysWithValues: namespaceProperties.map { ($0.key.rawValue, $0.value) })
        guard let orderValue = properties[orderKey] else {
            throw CanonicalFillLayerDecodingError.missingOrder
        }
        guard case .string(let order) = orderValue else {
            throw CanonicalFillLayerDecodingError.invalidOrder
        }

        let ids = try layerIdentifiers(in: order)
        guard Set(ids).count == ids.count else {
            throw CanonicalFillLayerDecodingError.duplicateLayerID
        }

        var expectedKeys: Set<String> = [orderKey]
        var decoded: [CanonicalFillLayer] = []
        decoded.reserveCapacity(ids.count)
        for id in ids {
            decoded.append(try layer(
                id: id,
                properties: properties,
                expectedKeys: &expectedKeys
            ))
        }
        guard Set(keys) == expectedKeys else {
            throw CanonicalFillLayerDecodingError.orphanedProperty
        }
        return .layers(decoded)
    }

    static func legacySolidLayer(for node: DocumentNode) -> CanonicalFillLayer? {
        let keys = ["style.fill.red", "style.fill.green", "style.fill.blue", "style.fill.alpha"]
        let channels = keys.compactMap(node.insertionNumberProperty)
        let color: CanonicalSolidColor
        let property: NodeProperty
        if channels.count == 4,
           let authored = node.insertionProperty("style.fill.red") {
            color = .init(red: channels[0], green: channels[1], blue: channels[2], alpha: channels[3])
            property = authored
        } else if node.insertionStringProperty("style.fill") == "surface",
                  let legacy = node.insertionProperty("style.fill") {
            color = .legacySurface
            property = legacy
        } else {
            return nil
        }
        guard color.isValid else { return nil }
        return .solid(id: FillLayerID(property.id.rawValue), color: color)
    }

    /// Produces the complete canonical property set for a layer snapshot. The
    /// caller replaces the v1 namespace atomically, so reorder/remove cannot
    /// leave a second ordering authority behind.
    static func propertyValues(for layers: [CanonicalFillLayer]) -> [String: PropertyValue] {
        var values: [String: PropertyValue] = [orderKey: .string(layers.map(\.id.description).joined(separator: ","))]
        for layer in layers {
            let prefix = "style.fill.layers.v1.\(layer.id.description)"
            values["\(prefix).kind"] = .string(layer.kind.rawValue)
            values["\(prefix).enabled"] = .boolean(layer.isEnabled)
            switch layer.kind {
            case .solid:
                guard let color = layer.solidColor else { continue }
                values["\(prefix).red"] = .number(color.red); values["\(prefix).green"] = .number(color.green)
                values["\(prefix).blue"] = .number(color.blue); values["\(prefix).alpha"] = .number(color.alpha)
            case .linearGradient:
                values["\(prefix).angle"] = .number(layer.normalizedAngleDegrees ?? 0)
                values["\(prefix).stops"] = .string(layer.stops.map(\.id.description).joined(separator: ","))
                for stop in layer.stops {
                    let stopPrefix = "\(prefix).stop.\(stop.id.description)"
                    values["\(stopPrefix).position"] = .number(stop.position)
                    values["\(stopPrefix).red"] = .number(stop.color.red); values["\(stopPrefix).green"] = .number(stop.color.green)
                    values["\(stopPrefix).blue"] = .number(stop.color.blue); values["\(stopPrefix).alpha"] = .number(stop.color.alpha)
                }
            }
        }
        return values
    }

    private static func layer(
        id: FillLayerID,
        properties: [String: PropertyValue],
        expectedKeys: inout Set<String>
    ) throws -> CanonicalFillLayer {
        let prefix = "style.fill.layers.v1.\(id.description)"
        let kindKey = "\(prefix).kind"
        let enabledKey = "\(prefix).enabled"
        expectedKeys.formUnion([kindKey, enabledKey])
        guard case .string(let kindValue)? = properties[kindKey],
              let kind = CanonicalFillLayerKind(rawValue: kindValue),
              case .boolean(let enabled)? = properties[enabledKey] else {
            throw CanonicalFillLayerDecodingError.invalidLayer
        }
        switch kind {
        case .solid:
            let color = try color(
                prefix: prefix,
                properties: properties,
                expectedKeys: &expectedKeys,
                error: .invalidLayer
            )
            let layer = CanonicalFillLayer.solid(id: id, color: color, isEnabled: enabled)
            guard layer.isValid else { throw CanonicalFillLayerDecodingError.invalidLayer }
            return layer
        case .linearGradient:
            let angleKey = "\(prefix).angle"
            let stopsKey = "\(prefix).stops"
            expectedKeys.formUnion([angleKey, stopsKey])
            guard case .number(let angle)? = properties[angleKey],
                  angle.isFinite, (0..<360).contains(angle),
                  case .string(let stopOrder)? = properties[stopsKey] else {
                throw CanonicalFillLayerDecodingError.invalidLayer
            }
            let stopIDs = try stopIdentifiers(in: stopOrder)
            guard stopIDs.count >= 2 else {
                throw CanonicalFillLayerDecodingError.invalidStopOrder
            }
            guard Set(stopIDs).count == stopIDs.count else {
                throw CanonicalFillLayerDecodingError.duplicateStopID
            }
            let stops = try stopIDs.map { stopID -> CanonicalGradientStop in
                let stopPrefix = "\(prefix).stop.\(stopID.description)"
                let positionKey = "\(stopPrefix).position"
                expectedKeys.insert(positionKey)
                guard case .number(let position)? = properties[positionKey],
                      position.isFinite, (0...1).contains(position) else {
                    throw CanonicalFillLayerDecodingError.invalidStop
                }
                let color = try color(
                    prefix: stopPrefix,
                    properties: properties,
                    expectedKeys: &expectedKeys,
                    error: .invalidStop
                )
                let stop = CanonicalGradientStop(id: stopID, position: position, color: color)
                guard stop.isValid else { throw CanonicalFillLayerDecodingError.invalidStop }
                return stop
            }
            let layer = CanonicalFillLayer.linearGradient(id: id, angleDegrees: angle, stops: stops, isEnabled: enabled)
            guard layer.isValid else { throw CanonicalFillLayerDecodingError.invalidLayer }
            return layer
        }
    }

    private static func color(
        prefix: String,
        properties: [String: PropertyValue],
        expectedKeys: inout Set<String>,
        error: CanonicalFillLayerDecodingError
    ) throws -> CanonicalSolidColor {
        let redKey = "\(prefix).red"
        let greenKey = "\(prefix).green"
        let blueKey = "\(prefix).blue"
        let alphaKey = "\(prefix).alpha"
        expectedKeys.formUnion([redKey, greenKey, blueKey, alphaKey])
        guard case .number(let red)? = properties[redKey],
              case .number(let green)? = properties[greenKey],
              case .number(let blue)? = properties[blueKey],
              case .number(let alpha)? = properties[alphaKey] else { throw error }
        let color = CanonicalSolidColor(red: red, green: green, blue: blue, alpha: alpha)
        guard color.isValid else { throw error }
        return color
    }

    private static func layerIdentifiers(in value: String) throws -> [FillLayerID] {
        if value.isEmpty { return [] }
        let tokens = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard tokens.allSatisfy({ !$0.isEmpty }) else {
            throw CanonicalFillLayerDecodingError.invalidOrder
        }
        return try tokens.map { token in
            guard let id = FillLayerID(uuidString: token), token == id.description else {
                throw CanonicalFillLayerDecodingError.invalidOrder
            }
            return id
        }
    }

    private static func stopIdentifiers(in value: String) throws -> [GradientStopID] {
        guard !value.isEmpty else { throw CanonicalFillLayerDecodingError.invalidStopOrder }
        let tokens = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard tokens.allSatisfy({ !$0.isEmpty }) else {
            throw CanonicalFillLayerDecodingError.invalidStopOrder
        }
        return try tokens.map { token in
            guard let id = GradientStopID(uuidString: token), token == id.description else {
                throw CanonicalFillLayerDecodingError.invalidStopOrder
            }
            return id
        }
    }

    private static func ownsNamespace(_ key: String) -> Bool {
        key == namespaceRoot || key.hasPrefix("\(namespaceRoot).")
    }
}

enum DesignInspectorValue: Equatable, Sendable {
    case unavailable(String), single(CanonicalSolidColor, PropertyOrigin), mixed
}

enum DesignInspectorOpacityValue: Equatable, Sendable { case unavailable(String), single(Double, PropertyOrigin), mixed }

/// A truthful projection of ordered fill layers across the current selection.
/// Shared rows are editable only when every applicable object owns the exact
/// same stable layer/stop identities and values. Differing stacks stay mixed;
/// the Inspector never borrows the primary object's rows and implies a bulk
/// mutation that the other selected objects cannot address by identity.
enum DesignFillLayerSelectionValue: Equatable, Sendable {
    case unavailable(String)
    case shared(layers: [CanonicalFillLayer], applicableCount: Int, skippedCount: Int)
    case mixed(applicableCount: Int, skippedCount: Int)
}

enum DesignInspectorEdit: Sendable { case fill(CanonicalSolidColor?), opacity(Double) }

/// Layer mutations are expressed as values only; the registry validates the
/// identity-bound selection and emits the existing atomic document command.
/// No Inspector control may write these properties directly.
enum DesignFillLayerEdit: Sendable {
    /// Compatibility operation for the existing single-colour Inspector. It
    /// resolves or creates one solid layer per applicable node so legacy
    /// controls migrate through the v1 write path rather than resurrecting
    /// v4 channel properties.
    case replaceSolid(CanonicalSolidColor?)
    case addSolid(id: FillLayerID, color: CanonicalSolidColor)
    case addLinearGradient(id: FillLayerID, angleDegrees: Double, stops: [CanonicalGradientStop])
    case remove(FillLayerID)
    case reorder(FillLayerID, to: Int)
    case setEnabled(FillLayerID, Bool)
    case setSolidColor(FillLayerID, CanonicalSolidColor)
    case setGradientAngle(FillLayerID, Double)
    case addStop(FillLayerID, CanonicalGradientStop, at: Int)
    case removeStop(FillLayerID, GradientStopID)
    case reorderStop(FillLayerID, GradientStopID, to: Int)
    case setStop(FillLayerID, GradientStopID, position: Double, color: CanonicalSolidColor)
}

enum DesignFillLayerEditError: Error, Equatable, Sendable {
    case missingLayer, missingStop, invalidIndex, invalidLayer, invalidStop
}

extension Array where Element == CanonicalFillLayer {
    func applying(_ edit: DesignFillLayerEdit) throws -> [CanonicalFillLayer] {
        var result = self
        func layerIndex(_ id: FillLayerID) throws -> Int {
            guard let index = result.firstIndex(where: { $0.id == id }) else { throw DesignFillLayerEditError.missingLayer }
            return index
        }
        switch edit {
        case .replaceSolid(let color):
            if let color {
                guard color.isValid else { throw DesignFillLayerEditError.invalidLayer }
                if let index = result.lastIndex(where: { $0.kind == .solid }) {
                    result[index] = .solid(id: result[index].id, color: color, isEnabled: result[index].isEnabled)
                } else {
                    result.append(.solid(color: color))
                }
            } else {
                result.removeAll { $0.kind == .solid }
            }
        case .addSolid(let id, let color):
            guard color.isValid, !result.contains(where: { $0.id == id }) else { throw DesignFillLayerEditError.invalidLayer }
            result.append(.solid(id: id, color: color))
        case .addLinearGradient(let id, let angle, let stops):
            let layer = CanonicalFillLayer.linearGradient(id: id, angleDegrees: angle, stops: stops)
            guard layer.isValid, !result.contains(where: { $0.id == id }) else { throw DesignFillLayerEditError.invalidLayer }
            result.append(layer)
        case .remove(let id): result.remove(at: try layerIndex(id))
        case .reorder(let id, let target):
            let source = try layerIndex(id); guard result.indices.contains(target) else { throw DesignFillLayerEditError.invalidIndex }
            let layer = result.remove(at: source); result.insert(layer, at: target)
        case .setEnabled(let id, let enabled):
            let index = try layerIndex(id); let layer = result[index]
            result[index] = CanonicalFillLayer(id: layer.id, kind: layer.kind, isEnabled: enabled, solidColor: layer.solidColor, angleDegrees: layer.angleDegrees, stops: layer.stops)
        case .setSolidColor(let id, let color):
            let index = try layerIndex(id); guard color.isValid, result[index].kind == .solid else { throw DesignFillLayerEditError.invalidLayer }
            result[index] = .solid(id: id, color: color, isEnabled: result[index].isEnabled)
        case .setGradientAngle(let id, let angle):
            let index = try layerIndex(id); let layer = result[index]
            guard layer.kind == .linearGradient, angle.isFinite else { throw DesignFillLayerEditError.invalidLayer }
            result[index] = .linearGradient(id: id, angleDegrees: angle, stops: layer.stops, isEnabled: layer.isEnabled)
        case .addStop(let id, let stop, let target):
            let index = try layerIndex(id); var layer = result[index]
            guard layer.kind == .linearGradient, stop.isValid, !layer.stops.contains(where: { $0.id == stop.id }), (0...layer.stops.count).contains(target) else { throw DesignFillLayerEditError.invalidStop }
            var stops = layer.stops
            stops.insert(stop, at: target)
            layer = .linearGradient(id: id, angleDegrees: layer.angleDegrees ?? 0, stops: stops, isEnabled: layer.isEnabled)
            guard layer.isValid else { throw DesignFillLayerEditError.invalidStop }; result[index] = layer
        case .removeStop(let id, let stopID):
            let index = try layerIndex(id); let layer = result[index]
            guard layer.kind == .linearGradient,
                  let stopIndex = layer.stops.firstIndex(where: { $0.id == stopID }),
                  layer.stops.count > 2 else { throw DesignFillLayerEditError.invalidStop }
            var stops = layer.stops
            stops.remove(at: stopIndex)
            result[index] = .linearGradient(id: id, angleDegrees: layer.angleDegrees ?? 0, stops: stops, isEnabled: layer.isEnabled)
        case .reorderStop(let id, let stopID, let target):
            let index = try layerIndex(id); let layer = result[index]
            guard layer.kind == .linearGradient,
                  let source = layer.stops.firstIndex(where: { $0.id == stopID }),
                  layer.stops.indices.contains(target) else { throw DesignFillLayerEditError.invalidStop }
            var stops = layer.stops
            let stop = stops.remove(at: source)
            stops.insert(stop, at: target)
            result[index] = .linearGradient(id: id, angleDegrees: layer.angleDegrees ?? 0, stops: stops, isEnabled: layer.isEnabled)
        case .setStop(let id, let stopID, let position, let color):
            let index = try layerIndex(id); let layer = result[index]
            guard layer.kind == .linearGradient, position.isFinite, (0...1).contains(position), color.isValid,
                  let stopIndex = layer.stops.firstIndex(where: { $0.id == stopID }) else { throw DesignFillLayerEditError.invalidStop }
            var stops = layer.stops
            stops[stopIndex] = .init(id: stopID, position: position, color: color)
            result[index] = .linearGradient(id: id, angleDegrees: layer.angleDegrees ?? 0, stops: stops, isEnabled: layer.isEnabled)
        }
        guard Set(result.map(\.id)).count == result.count, result.allSatisfy(\.isValid) else { throw DesignFillLayerEditError.invalidLayer }
        return result
    }
}

/// The initiating native control is retained only for bounded, redacted
/// diagnostics. Canonical mutations still travel through the same registry.
enum DesignInspectorProvenance: String, Codable, Sendable { case picker, stepper, hexadecimal, keyboard, focusLoss, accessibility, automation }

struct DesignInspectorOperationIdentity: Equatable, Sendable {
    let documentID: DocumentID
    let pageID: PageID
    let revision: UInt64
    let sceneID: CanvasViewportSceneID
    let rendererGeneration: UInt64
}

struct DesignInspectorCommand: Sendable {
    let identity: DesignInspectorOperationIdentity
    let orderedNodeIDs: [NodeID]
    let edit: DesignInspectorEdit
    let provenance: DesignInspectorProvenance
    let cancelled: Bool
}

/// Identity-gated layer operation. This deliberately shares the same scene,
/// selection and renderer preconditions as the existing solid/opacity command;
/// the Inspector only supplies a value edit, never direct property mutation.
struct DesignFillLayerCommand: Sendable {
    let identity: DesignInspectorOperationIdentity
    let orderedNodeIDs: [NodeID]
    let edit: DesignFillLayerEdit
    let provenance: DesignInspectorProvenance
    let cancelled: Bool
}

struct PreparedDesignInspectorEdit: Sendable {
    let applicableNodeIDs: [NodeID]
    let skippedNodeIDs: [NodeID]
    /// A bounded, non-content explanation for every intentionally skipped
    /// selection target. This keeps mixed-selection behavior inspectable
    /// without making unsupported kinds look as if they were edited.
    let skippedReasons: [NodeID: String]
    let documentCommand: DocumentCommand
}

enum DesignInspectorError: Error, LocalizedError, Equatable, Sendable {
    case unavailable(String), stale, invalidColor, invalidOpacity, noApplicableTargets, noChanges
    var errorDescription: String? { switch self {
    case .unavailable(let reason): reason
    case .stale: "The document, selection, or canvas changed before the Design edit could commit."
    case .invalidColor: "Enter a complete #RRGGBB or #RRGGBBAA color."
    case .invalidOpacity: "Opacity must be a finite value from 0 through 100 percent."
    case .noApplicableTargets: "The selected objects do not support solid background fills."
    case .noChanges: "The authored appearance already has that value."
    } }
}

struct DesignInspectorCommandRegistry: Sendable {
    static let requirementIDs: Set<String> = ["SF-0508-001", "SF-0508-002", "SF-0508-003", "SF-0508-004", "SF-0508-005", "SF-0508-006", "SF-0508-007", "SF-0508-008"]
    static let fillKinds: Set<NodeKind> = [.frame, .section, .stack, .grid]

    /// The v5 layer representation wins whenever its order key is present.
    /// This prevents a migrated document from consulting legacy RGBA fields as
    /// a second visual authority; an empty but valid v5 order means no fill.
    static func resolvedLayers(for node: DocumentNode) -> [CanonicalFillLayer] {
        guard fillKinds.contains(node.kind) else { return [] }
        if let layers = CanonicalFillLayerCodec.layers(for: node) { return layers }
        return CanonicalFillLayerCodec.legacySolidLayer(for: node).map { [$0] } ?? []
    }

    static func fillLayerSelectionValue(nodes: [DocumentNode]) -> DesignFillLayerSelectionValue {
        guard !nodes.isEmpty else {
            return .unavailable("Select a Frame, Section, Stack, or Grid to edit fill layers.")
        }
        let applicable = nodes.filter { fillKinds.contains($0.kind) }
        guard !applicable.isEmpty else {
            return .unavailable("The selected objects do not support background fill layers.")
        }
        let stacks = applicable.map(resolvedLayers)
        let skippedCount = nodes.count - applicable.count
        guard let first = stacks.first,
              stacks.dropFirst().allSatisfy({ $0 == first }) else {
            return .mixed(applicableCount: applicable.count, skippedCount: skippedCount)
        }
        return .shared(
            layers: first,
            applicableCount: applicable.count,
            skippedCount: skippedCount
        )
    }

    static func resolvedFill(for node: DocumentNode) -> (CanonicalSolidColor?, PropertyOrigin) {
        guard fillKinds.contains(node.kind) else { return (nil, .defaulted) }
        if let layers = CanonicalFillLayerCodec.layers(for: node) {
            // A layer document has a single authoritative source. The legacy
            // keys must never influence the Design summary after migration.
            guard let solid = layers.last(where: { $0.isEnabled && $0.kind == .solid }),
                  let color = solid.solidColor else { return (nil, .defaulted) }
            let key = "style.fill.layers.v1.\(solid.id.description).red"
            return (color, node.insertionProperty(key)?.origin ?? .authored)
        }
        let keys = ["style.fill.red", "style.fill.green", "style.fill.blue", "style.fill.alpha"]
        let channels = keys.compactMap(node.insertionNumberProperty)
        if channels.count == 4 {
            let color = CanonicalSolidColor(red: channels[0], green: channels[1], blue: channels[2], alpha: channels[3])
            if color.isValid { return (color, node.insertionProperty("style.fill.red")?.origin ?? .authored) }
        }
        // schema-v4 legacy default: `surface` was a renderer label only. It
        // deterministically resolves to this v1 neutral surface until removed.
        return node.insertionStringProperty("style.fill") == "surface" ? (.legacySurface, .defaulted) : (nil, .defaulted)
    }

    static func resolvedOpacity(for node: DocumentNode) -> (Double, PropertyOrigin)? {
        guard fillKinds.contains(node.kind) || node.kind == .text else { return nil }
        if let value = node.insertionNumberProperty("style.opacity"), value.isFinite, (0...1).contains(value) {
            return (value, node.insertionProperty("style.opacity")?.origin ?? .authored)
        }
        return (1, .defaulted)
    }

    static func fillValue(nodes: [DocumentNode]) -> DesignInspectorValue {
        let values = nodes.map(resolvedFill)
        guard !values.isEmpty, values.contains(where: { $0.0 != nil }) else { return .unavailable("Select a Frame, Section, Stack, or Grid to edit its fill.") }
        guard let first = values.first else { return .unavailable("No solid fill is applied.") }
        guard values.allSatisfy({ $0.0 == first.0 }) else { return .mixed }
        guard let color = first.0 else { return .unavailable("No solid fill is applied.") }
        return .single(color, values.first!.1)
    }

    static func opacityValue(nodes: [DocumentNode]) -> DesignInspectorOpacityValue {
        let values = nodes.compactMap(resolvedOpacity)
        guard !values.isEmpty else { return .unavailable("The selected objects do not support opacity.") }
        guard values.allSatisfy({ $0.0 == values.first!.0 }) else { return .mixed }
        return .single(values[0].0, values[0].1)
    }

    func prepare(_ command: DesignInspectorCommand, in document: CanonicalDocument, context: TransformValidationContext) throws -> PreparedDesignInspectorEdit {
        guard !command.cancelled else { throw DesignInspectorError.unavailable("The Design edit was cancelled; committed appearance is unchanged.") }
        if case .fill(let color) = command.edit {
            if let color, !color.isValid { throw DesignInspectorError.invalidColor }
            // The compatibility solid-fill entry point delegates to the sole
            // v1 layer registry. It must never write the retired v4 channel
            // keys or create a second appearance authority.
            return try prepare(
                DesignFillLayerCommand(
                    identity: command.identity,
                    orderedNodeIDs: command.orderedNodeIDs,
                    edit: .replaceSolid(color),
                    provenance: command.provenance,
                    cancelled: false
                ),
                in: document,
                context: context
            )
        }
        guard command.identity.documentID == document.id, command.identity.revision == document.revision else { throw DesignInspectorError.stale }
        guard command.identity.pageID == context.activePageID,
              command.identity.sceneID == context.currentSceneID,
              command.identity.rendererGeneration == context.rendererGeneration else { throw DesignInspectorError.stale }
        guard command.orderedNodeIDs == context.selectedNodeIDs, !command.orderedNodeIDs.isEmpty else { throw DesignInspectorError.stale }
        guard Set(command.orderedNodeIDs).count == command.orderedNodeIDs.count else { throw DesignInspectorError.unavailable("A Design edit cannot contain the same object twice.") }
        guard document.revision < UInt64.max else { throw DesignInspectorError.unavailable("The document revision cannot accept another Design edit.") }
        guard let page = document.pages.first(where: { $0.id == command.identity.pageID }) else { throw DesignInspectorError.unavailable("The active page is unavailable.") }
        guard case .opacity(let opacity) = command.edit else {
            throw DesignInspectorError.unavailable("The Design edit is unavailable.")
        }
        guard opacity.isFinite, (0...1).contains(opacity) else { throw DesignInspectorError.invalidOpacity }
        var applicable: [NodeID] = [], skipped: [NodeID] = [], skippedReasons: [NodeID: String] = [:], changes: [DocumentCommand] = []
        for id in command.orderedNodeIDs {
            guard let node = page.nodes.first(where: { $0.id == id }) else { throw DesignInspectorError.unavailable("A selected object no longer exists.") }
            guard context.availableNodeIDs.contains(id), !node.selectionBooleanProperty("hidden"), !node.selectionBooleanProperty("locked") else { throw DesignInspectorError.unavailable("A selected object is unavailable, hidden, or locked.") }
            let applies = Self.resolvedOpacity(for: node) != nil
            guard applies else {
                skipped.append(id)
                skippedReasons[id] = "This object kind does not support this appearance property."
                continue
            }
            applicable.append(id)
            let old = node.insertionProperty("style.opacity")
            guard old?.value != .number(opacity) || old?.origin != .authored else { continue }
            changes.append(.setProperty(SetPropertyCommand(pageID: page.id, nodeID: id, property: NodeProperty(id: old?.id ?? PropertyID(), key: .init(rawValue: "style.opacity"), value: .number(opacity), origin: .authored))))
        }
        guard !applicable.isEmpty else { throw DesignInspectorError.noApplicableTargets }
        guard !changes.isEmpty else { throw DesignInspectorError.noChanges }
        return PreparedDesignInspectorEdit(applicableNodeIDs: applicable, skippedNodeIDs: skipped, skippedReasons: skippedReasons, documentCommand: .batch(changes))
    }

    /// Compiles one complete layer snapshot per applicable target. v1 keys are
    /// replaced as a namespace in one batch, while v4 fill keys are removed in
    /// that same transaction. CommandRegistry supplies the exact inverse,
    /// including property IDs, origins and prior ordering.
    func prepare(_ command: DesignFillLayerCommand, in document: CanonicalDocument, context: TransformValidationContext) throws -> PreparedDesignInspectorEdit {
        guard !command.cancelled else {
            throw DesignInspectorError.unavailable("The Design layer edit was cancelled; committed appearance is unchanged.")
        }
        guard context.isLifecycleAvailable else {
            throw DesignInspectorError.unavailable(context.lifecycleDisabledReason ?? "Design editing is unavailable during the current document operation.")
        }
        guard command.identity.documentID == document.id,
              command.identity.revision == document.revision,
              command.identity.pageID == context.activePageID,
              command.identity.sceneID == context.currentSceneID,
              command.identity.rendererGeneration == context.rendererGeneration else {
            throw DesignInspectorError.stale
        }
        guard command.orderedNodeIDs == context.selectedNodeIDs, !command.orderedNodeIDs.isEmpty else {
            throw DesignInspectorError.stale
        }
        guard Set(command.orderedNodeIDs).count == command.orderedNodeIDs.count else {
            throw DesignInspectorError.unavailable("A Design layer edit cannot contain the same object twice.")
        }
        guard document.revision < UInt64.max else {
            throw DesignInspectorError.unavailable("The document revision cannot accept another Design layer edit.")
        }
        guard let page = document.pages.first(where: { $0.id == command.identity.pageID }) else {
            throw DesignInspectorError.unavailable("The active page is unavailable.")
        }

        var applicable: [NodeID] = []
        var skipped: [NodeID] = []
        var skippedReasons: [NodeID: String] = [:]
        var changes: [DocumentCommand] = []
        let legacyKeys: Set<String> = ["style.fill", "style.fill.red", "style.fill.green", "style.fill.blue", "style.fill.alpha"]

        for id in command.orderedNodeIDs {
            guard let node = page.nodes.first(where: { $0.id == id }) else {
                throw DesignInspectorError.unavailable("A selected object no longer exists.")
            }
            guard context.availableNodeIDs.contains(id),
                  !node.selectionBooleanProperty("hidden"),
                  !node.selectionBooleanProperty("locked") else {
                throw DesignInspectorError.unavailable("A selected object is unavailable, hidden, or locked.")
            }
            guard Self.fillKinds.contains(node.kind) else {
                skipped.append(id)
                skippedReasons[id] = "This object kind does not support background fill layers."
                continue
            }

            let before = Self.resolvedLayers(for: node)
            let after: [CanonicalFillLayer]
            do {
                after = try before.applying(command.edit)
            } catch {
                // Error text deliberately carries only the property category,
                // never node names, document paths, or user-authored content.
                throw DesignInspectorError.unavailable("The requested fill-layer values are invalid.")
            }
            applicable.append(id)
            guard after != before || CanonicalFillLayerCodec.layers(for: node) == nil else { continue }

            let desired = CanonicalFillLayerCodec.propertyValues(for: after)
            let owned = node.properties.filter {
                $0.key.rawValue.hasPrefix("style.fill.layers.v1.") || legacyKeys.contains($0.key.rawValue)
            }
            let ownedByKey = Dictionary(uniqueKeysWithValues: owned.map { ($0.key.rawValue, $0) })

            // Deterministic lexical order makes the forward transaction
            // inspectable and preserves stable IDs when a property survives.
            for key in desired.keys.sorted() {
                guard let value = desired[key] else { continue }
                let old = ownedByKey[key]
                guard old?.value != value || old?.origin != .authored else { continue }
                changes.append(.setProperty(.init(
                    pageID: page.id,
                    nodeID: id,
                    property: .init(id: old?.id ?? PropertyID(), key: .init(rawValue: key), value: value, origin: .authored)
                )))
            }
            for old in owned.sorted(by: { $0.key.rawValue < $1.key.rawValue }) where desired[old.key.rawValue] == nil {
                changes.append(.removeProperty(.init(pageID: page.id, nodeID: id, propertyID: old.id)))
            }
        }

        guard !applicable.isEmpty else { throw DesignInspectorError.noApplicableTargets }
        guard !changes.isEmpty else { throw DesignInspectorError.noChanges }
        let documentCommand: DocumentCommand = .batch(changes)
        guard CommandRegistry().availability(for: documentCommand, in: document).isEnabled else {
            throw DesignInspectorError.unavailable("The fill-layer edit is no longer valid for the active document.")
        }
        return .init(
            applicableNodeIDs: applicable,
            skippedNodeIDs: skipped,
            skippedReasons: skippedReasons,
            documentCommand: documentCommand
        )
    }
}

enum TransformSessionIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "transform-session"
}
typealias TransformSessionID = StableIdentifier<TransformSessionIdentifierDomain>

enum TransformHandle: String, Codable, CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

enum TransformAxisConstraint: String, Codable, Sendable {
    case none, horizontal, vertical
}

enum TransformProvenance: String, Codable, CaseIterable, Sendable {
    case pointer, keyboard, menu, contextualMenu, accessibility, automation
}

enum TransformOperation: Equatable, Sendable {
    case move(delta: WorldVector, constraint: TransformAxisConstraint)
    case resize(handle: TransformHandle, delta: WorldVector, constraint: TransformAxisConstraint)

    var name: String {
        switch self {
        case .move: "move"
        case .resize: "resize"
        }
    }
}

struct TransformOperationIdentity: Equatable, Sendable {
    let sessionID: TransformSessionID
    let documentID: DocumentID
    let pageID: PageID
    let revision: UInt64
    let sceneID: CanvasViewportSceneID
    let rendererGeneration: UInt64
}

struct GeometryTransformCommand: Equatable, Sendable {
    let identity: TransformOperationIdentity
    let orderedNodeIDs: [NodeID]
    let operation: TransformOperation
    let provenance: TransformProvenance
}

struct TransformValidationContext: Sendable {
    let activePageID: PageID
    let currentSceneID: CanvasViewportSceneID
    let rendererGeneration: UInt64
    let selectedNodeIDs: [NodeID]
    let availableNodeIDs: Set<NodeID>
    let isLifecycleAvailable: Bool
    let lifecycleDisabledReason: String?
}

enum TransformError: Error, Equatable, LocalizedError, Sendable {
    case lifecycleUnavailable(String)
    case emptySelection
    case duplicateTarget
    case staleDocument
    case staleRevision
    case revisionExhausted
    case staleRenderer
    case pageUnavailable
    case crossPageTarget
    case selectionMismatch
    case missingTarget
    case lockedTarget
    case hiddenTarget
    case unavailableTarget
    case incompatibleGeometry
    case incompatibleMultipleResize
    case invalidDelta
    case invalidResult
    case cancelled

    var errorDescription: String? {
        switch self {
        case .lifecycleUnavailable(let reason): reason
        case .emptySelection: "Select a transformable object before moving or resizing."
        case .duplicateTarget: "A transform cannot contain the same stable object identity twice."
        case .staleDocument: "A different document now owns this transform."
        case .staleRevision: "The document changed before the transform could commit."
        case .revisionExhausted: "The document revision cannot accept another transform."
        case .staleRenderer: "A newer rendered scene replaced this transform."
        case .pageUnavailable: "The active transform page is no longer available."
        case .crossPageTarget: "All transformed objects must belong to the active page."
        case .selectionMismatch: "The ordered selection changed before the transform could commit."
        case .missingTarget: "A selected transform object no longer exists."
        case .lockedTarget: "Locked objects can be inspected but cannot be transformed."
        case .hiddenTarget: "Hidden objects cannot be transformed."
        case .unavailableTarget: "An object is unavailable in the current rendered scene."
        case .incompatibleGeometry: "Every target must have explicit finite authored geometry."
        case .incompatibleMultipleResize: "Resize one object at a time; multiple-selection resize is not supported by this bounded slice."
        case .invalidDelta: "Transform values must be finite and within the supported geometry range."
        case .invalidResult: "The requested transform would produce invalid geometry."
        case .cancelled: "The transform was cancelled; committed geometry is unchanged."
        }
    }
}

struct TransformAvailability: Equatable, Sendable {
    let isEnabled: Bool
    let disabledReason: String?

    static let enabled = Self(isEnabled: true, disabledReason: nil)
    static func disabled(_ reason: String) -> Self {
        Self(isEnabled: false, disabledReason: reason)
    }
}

struct TransformCancellation: Sendable {
    let isCancelled: @Sendable () -> Bool
    static let never = Self(isCancelled: { false })
}

struct TransformGeometry: Codable, Equatable, Sendable {
    let nodeID: NodeID
    let original: WorldRect
    let preview: WorldRect
}

struct PreparedTransform: Equatable, Sendable {
    let identity: TransformOperationIdentity
    let operation: TransformOperation
    let geometries: [TransformGeometry]
    let documentCommand: DocumentCommand
}

enum TransformPolicy {
    static let minimumDimension = 1.0
    static let keyboardStep = 1.0
    static let keyboardLargeStep = 10.0
    static let handleHitRadius = 10.0
}

// MARK: - Fixed geometry Inspector

enum GeometryInspectorIdentifierDomain: StableIdentifierDomain {
    static let diagnosticNamespace = "geometry-inspector"
}
typealias GeometryInspectorEditID = StableIdentifier<GeometryInspectorIdentifierDomain>

enum GeometryInspectorProvenance: String, Codable, CaseIterable, Sendable {
    case pointer
    case keyboard
    case accessibility
    case automation
}

struct GeometryInspectorOperationIdentity: Equatable, Sendable {
    let editID: GeometryInspectorEditID
    let documentID: DocumentID
    let pageID: PageID
    let revision: UInt64
    let sceneID: CanvasViewportSceneID
    let rendererGeneration: UInt64
}

struct GeometryInspectorCommand: Equatable, Sendable {
    let identity: GeometryInspectorOperationIdentity
    let orderedNodeIDs: [NodeID]
    let field: GeometryInspectorField
    let value: Double
    let provenance: GeometryInspectorProvenance
    var breakpoint: ResponsiveBreakpoint = .desktop
    var removesOverride = false
}

enum GeometryInspectorError: Error, Equatable, LocalizedError, Sendable {
    case lifecycleUnavailable(String)
    case emptySelection
    case duplicateTarget
    case staleDocument
    case staleRevision
    case staleRenderer
    case pageUnavailable
    case selectionMismatch
    case revisionExhausted
    case missingTarget
    case lockedTarget
    case hiddenTarget
    case unavailableTarget
    case noApplicableTargets
    case invalidValue
    case cancelled

    var errorDescription: String? {
        switch self {
        case .lifecycleUnavailable(let reason): reason
        case .emptySelection: "Select an object with editable geometry first."
        case .duplicateTarget: "A geometry edit cannot contain the same object twice."
        case .staleDocument: "A different document now owns this Inspector edit."
        case .staleRevision: "The document changed before the Inspector edit could commit."
        case .staleRenderer: "A newer canvas scene replaced this Inspector edit."
        case .pageUnavailable: "The active page is no longer available."
        case .selectionMismatch: "The selection changed before the Inspector edit could commit."
        case .revisionExhausted: "The document revision cannot accept another geometry edit."
        case .missingTarget: "A selected object no longer exists."
        case .lockedTarget: "Locked objects can be inspected but not edited."
        case .hiddenTarget: "Hidden objects cannot be edited from Layout."
        case .unavailableTarget: "An object is unavailable in the current canvas scene."
        case .noApplicableTargets: "The selected objects do not support fixed geometry editing."
        case .invalidValue: "Enter a finite value within the supported geometry range. Width and Height must be at least 1."
        case .cancelled: "The Inspector edit was cancelled; committed geometry is unchanged."
        }
    }
}

struct PreparedGeometryInspectorEdit: Equatable, Sendable {
    let identity: GeometryInspectorOperationIdentity
    let field: GeometryInspectorField
    let value: Double
    /// IDs deliberately excluded because their node kind has no fixed geometry
    /// contract. UI presents this count explicitly instead of coercing them.
    let skippedNodeIDs: [NodeID]
    let documentCommand: DocumentCommand
    let breakpoint: ResponsiveBreakpoint
    let removesOverride: Bool
}

enum GeometryInspectorValue: Equatable, Sendable {
    case unavailable(String)
    case single(value: Double, origin: PropertyOrigin)
    case mixed
}

struct GeometryInspectorCommandRegistry: Sendable {
    static let requirementIDs: Set<String> = [
        "SF-0403-001", "SF-0403-002", "SF-0403-003", "SF-0403-004",
        "SF-0403-005", "SF-0403-006", "SF-0403-007", "SF-0403-008",
    ]
    static let responsiveRequirementIDs: Set<String> = [
        "SF-0601-001", "SF-0601-002", "SF-0601-003", "SF-0601-004",
        "SF-0601-005", "SF-0601-006", "SF-0601-008",
        "SF-0602-001", "SF-0602-002", "SF-0602-003", "SF-0602-004",
        "SF-0602-005", "SF-0602-006", "SF-0602-008",
    ]

    private static let supportedKinds: Set<NodeKind> = [.frame, .text, .section, .stack, .grid]

    static func supportsFixedGeometry(_ kind: NodeKind) -> Bool {
        supportedKinds.contains(kind)
    }

    func value(
        for field: GeometryInspectorField,
        in document: CanonicalDocument,
        context: TransformValidationContext,
        breakpoint: ResponsiveBreakpoint = .desktop
    ) -> GeometryInspectorValue {
        guard !context.selectedNodeIDs.isEmpty else {
            return .unavailable("Select an object with editable geometry first.")
        }
        let nodes = context.selectedNodeIDs.compactMap { id in
            document.pages.first(where: { $0.id == context.activePageID })?.nodes.first(where: { $0.id == id })
        }.filter { Self.supportsFixedGeometry($0.kind) }
        guard !nodes.isEmpty else {
            return .unavailable("The selected objects do not support fixed geometry editing.")
        }
        let values = nodes.compactMap { node -> (Double, PropertyOrigin)? in
            ResponsiveGeometryResolver.value(for: field, node: node, breakpoint: breakpoint).map { ($0.0, $0.1) }
        }
        guard values.count == nodes.count, let first = values.first else {
            return .unavailable("The selected objects have invalid authored geometry.")
        }
        return values.dropFirst().allSatisfy { $0.0 == first.0 }
            ? .single(value: first.0, origin: first.1)
            : .mixed
    }

    func prepare(
        _ command: GeometryInspectorCommand,
        in document: CanonicalDocument,
        context: TransformValidationContext,
        cancellation: TransformCancellation = .never
    ) throws -> PreparedGeometryInspectorEdit {
        guard !cancellation.isCancelled() else { throw GeometryInspectorError.cancelled }
        guard context.isLifecycleAvailable else {
            throw GeometryInspectorError.lifecycleUnavailable(
                context.lifecycleDisabledReason ?? "Layout editing is unavailable during the current document operation."
            )
        }
        guard command.identity.documentID == document.id else { throw GeometryInspectorError.staleDocument }
        guard command.identity.revision == document.revision else { throw GeometryInspectorError.staleRevision }
        guard document.revision < UInt64.max else { throw GeometryInspectorError.revisionExhausted }
        guard command.identity.pageID == context.activePageID,
              let page = document.pages.first(where: { $0.id == context.activePageID }) else {
            throw GeometryInspectorError.pageUnavailable
        }
        guard command.identity.sceneID == context.currentSceneID,
              command.identity.rendererGeneration == context.rendererGeneration else {
            throw GeometryInspectorError.staleRenderer
        }
        guard !command.orderedNodeIDs.isEmpty else { throw GeometryInspectorError.emptySelection }
        guard Set(command.orderedNodeIDs).count == command.orderedNodeIDs.count else {
            throw GeometryInspectorError.duplicateTarget
        }
        guard command.orderedNodeIDs == context.selectedNodeIDs else {
            throw GeometryInspectorError.selectionMismatch
        }
        guard command.removesOverride || Self.isValid(command.value, for: command.field) else { throw GeometryInspectorError.invalidValue }

        var commands: [DocumentCommand] = []
        var skipped: [NodeID] = []
        for id in command.orderedNodeIDs {
            guard !cancellation.isCancelled() else { throw GeometryInspectorError.cancelled }
            guard let node = page.nodes.first(where: { $0.id == id }) else {
                throw GeometryInspectorError.missingTarget
            }
            guard Self.supportsFixedGeometry(node.kind) else {
                skipped.append(id)
                continue
            }
            guard !node.insertionBooleanProperty("locked") else { throw GeometryInspectorError.lockedTarget }
            guard !node.insertionBooleanProperty("hidden") else { throw GeometryInspectorError.hiddenTarget }
            guard context.availableNodeIDs.contains(id) else { throw GeometryInspectorError.unavailableTarget }
            if command.breakpoint == .desktop {
                guard !command.removesOverride,
                      let property = node.insertionProperty(command.field.propertyKey) else { skipped.append(id); continue }
                commands.append(.setProperty(.init(pageID: page.id, nodeID: id,
                    property: .init(id: property.id, key: property.key, value: .number(command.value), origin: .authored))))
            } else {
                let key = ResponsiveGeometryResolver.key(command.field, breakpoint: command.breakpoint)
                if let property = node.insertionProperty(key) {
                    commands.append(command.removesOverride
                        ? .removeProperty(.init(pageID: page.id, nodeID: id, propertyID: property.id))
                        : .setProperty(.init(pageID: page.id, nodeID: id,
                            property: .init(id: property.id, key: property.key, value: .number(command.value), origin: .authored))))
                } else if !command.removesOverride {
                    commands.append(.setProperty(.init(pageID: page.id, nodeID: id,
                        property: .init(key: .init(rawValue: key), value: .number(command.value), origin: .authored),
                        insertionIndex: node.properties.count)))
                }
            }
        }
        guard !commands.isEmpty else { throw GeometryInspectorError.noApplicableTargets }
        let documentCommand = DocumentCommand.batch(commands)
        guard CommandRegistry().availability(for: documentCommand, in: document).isEnabled else {
            throw GeometryInspectorError.invalidValue
        }
        return .init(
            identity: command.identity,
            field: command.field,
            value: command.value,
            skippedNodeIDs: skipped,
            documentCommand: documentCommand,
            breakpoint: command.breakpoint,
            removesOverride: command.removesOverride
        )
    }

    static func isValid(_ value: Double, for field: GeometryInspectorField) -> Bool {
        guard value.isFinite, abs(value) <= LayoutPolicy.maximumDimension else { return false }
        return !field.requiresPositiveValue || value >= TransformPolicy.minimumDimension
    }
}

enum GeometryInspectorNumberParser {
    static func parse(_ input: String, locale: Locale = .current) -> Result<Double, GeometryInspectorError> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.invalidValue) }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.isLenient = false
        // A draft such as `-` or `12.` is useful while typing, but is not a
        // complete canonical number and must never commit merely because
        // NumberFormatter accepts a numeric prefix.
        let decimalSeparator = formatter.decimalSeparator ?? "."
        guard trimmed != "+", trimmed != "-", trimmed != "−",
              !trimmed.hasSuffix(decimalSeparator) else {
            return .failure(.invalidValue)
        }
        let allowed = CharacterSet.decimalDigits.union(CharacterSet(charactersIn:
            "+-−" + decimalSeparator + (formatter.groupingSeparator ?? "")
        ))
        guard trimmed.unicodeScalars.allSatisfy(allowed.contains) else {
            return .failure(.invalidValue)
        }
        guard let number = formatter.number(from: trimmed) else { return .failure(.invalidValue) }
        let value = number.doubleValue
        return value.isFinite ? .success(value) : .failure(.invalidValue)
    }

    static func format(_ value: Double, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        formatter.minimumFractionDigits = 0
        return formatter.string(from: value as NSNumber) ?? String(format: "%.3f", value)
    }
}

struct TransformCommandRegistry: Sendable {
    static let requirementIDs: Set<String> = [
        "SF-0403-001", "SF-0403-002", "SF-0403-003", "SF-0403-004",
        "SF-0403-005", "SF-0403-006", "SF-0403-007", "SF-0403-008",
    ]

    func availability(
        for command: GeometryTransformCommand,
        in document: CanonicalDocument,
        context: TransformValidationContext
    ) -> TransformAvailability {
        do {
            _ = try prepare(command, in: document, context: context)
            return .enabled
        } catch {
            return .disabled(error.localizedDescription)
        }
    }

    func prepare(
        _ command: GeometryTransformCommand,
        in document: CanonicalDocument,
        context: TransformValidationContext,
        cancellation: TransformCancellation = .never
    ) throws -> PreparedTransform {
        guard !cancellation.isCancelled() else { throw TransformError.cancelled }
        guard context.isLifecycleAvailable else {
            throw TransformError.lifecycleUnavailable(
                context.lifecycleDisabledReason ?? "Transforms are unavailable during the current document operation."
            )
        }
        guard command.identity.documentID == document.id else { throw TransformError.staleDocument }
        guard command.identity.revision == document.revision else { throw TransformError.staleRevision }
        guard document.revision < UInt64.max else { throw TransformError.revisionExhausted }
        guard command.identity.pageID == context.activePageID,
              let page = document.pages.first(where: { $0.id == context.activePageID }) else {
            throw TransformError.pageUnavailable
        }
        guard command.identity.sceneID == context.currentSceneID,
              command.identity.rendererGeneration == context.rendererGeneration else {
            throw TransformError.staleRenderer
        }
        guard !command.orderedNodeIDs.isEmpty else { throw TransformError.emptySelection }
        guard Set(command.orderedNodeIDs).count == command.orderedNodeIDs.count else {
            throw TransformError.duplicateTarget
        }
        guard command.orderedNodeIDs == context.selectedNodeIDs else {
            throw TransformError.selectionMismatch
        }
        if case .resize = command.operation, command.orderedNodeIDs.count != 1 {
            throw TransformError.incompatibleMultipleResize
        }
        try validateOperation(command.operation)

        var geometries: [TransformGeometry] = []
        geometries.reserveCapacity(command.orderedNodeIDs.count)
        var mutations: [DocumentCommand] = []
        mutations.reserveCapacity(command.orderedNodeIDs.count * 4)
        for id in command.orderedNodeIDs {
            guard !cancellation.isCancelled() else { throw TransformError.cancelled }
            guard let node = page.nodes.first(where: { $0.id == id }) else {
                if document.pages.drop(while: { $0.id != page.id }).dropFirst().contains(where: {
                    $0.nodes.contains(where: { $0.id == id })
                }) || document.pages.prefix(while: { $0.id != page.id }).contains(where: {
                    $0.nodes.contains(where: { $0.id == id })
                }) {
                    throw TransformError.crossPageTarget
                }
                throw TransformError.missingTarget
            }
            guard !node.insertionBooleanProperty("locked") else { throw TransformError.lockedTarget }
            guard !node.insertionBooleanProperty("hidden") else { throw TransformError.hiddenTarget }
            guard context.availableNodeIDs.contains(id) else { throw TransformError.unavailableTarget }
            guard let original = node.insertionGeometry?.frame else {
                throw TransformError.incompatibleGeometry
            }
            let preview = try Self.resolve(original, operation: command.operation)
            geometries.append(TransformGeometry(nodeID: id, original: original, preview: preview))
            mutations.append(contentsOf: try propertyCommands(
                pageID: page.id, node: node, frame: preview, operation: command.operation
            ))
        }
        guard !cancellation.isCancelled() else { throw TransformError.cancelled }
        let documentCommand = DocumentCommand.batch(mutations)
        guard CommandRegistry().availability(for: documentCommand, in: document).isEnabled else {
            throw TransformError.invalidResult
        }
        return PreparedTransform(
            identity: command.identity,
            operation: command.operation,
            geometries: geometries,
            documentCommand: documentCommand
        )
    }

    static func resolve(_ frame: WorldRect, operation: TransformOperation) throws -> WorldRect {
        guard frame.isValid else { throw TransformError.incompatibleGeometry }
        switch operation {
        case .move(let rawDelta, let constraint):
            let delta = constrained(rawDelta, constraint: constraint)
            return try validated(WorldRect(
                origin: WorldPoint(x: frame.origin.x + delta.dx, y: frame.origin.y + delta.dy),
                size: frame.size
            ))
        case .resize(let handle, let rawDelta, let constraint):
            let delta = constrained(rawDelta, constraint: constraint)
            var x = frame.origin.x
            var y = frame.origin.y
            var width = frame.size.width
            var height = frame.size.height
            if [.topLeft, .left, .bottomLeft].contains(handle) {
                x += delta.dx
                width -= delta.dx
            }
            if [.topRight, .right, .bottomRight].contains(handle) {
                width += delta.dx
            }
            if [.topLeft, .top, .topRight].contains(handle) {
                y += delta.dy
                height -= delta.dy
            }
            if [.bottomLeft, .bottom, .bottomRight].contains(handle) {
                height += delta.dy
            }
            return try validated(WorldRect(
                origin: WorldPoint(x: x, y: y),
                size: WorldSize(width: width, height: height)
            ))
        }
    }

    private static func constrained(
        _ delta: WorldVector,
        constraint: TransformAxisConstraint
    ) -> WorldVector {
        switch constraint {
        case .none: delta
        case .horizontal: WorldVector(dx: delta.dx, dy: 0)
        case .vertical: WorldVector(dx: 0, dy: delta.dy)
        }
    }

    private static func validated(_ frame: WorldRect) throws -> WorldRect {
        let values = [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height]
        guard values.allSatisfy(\.isFinite),
              abs(frame.origin.x) <= LayoutPolicy.maximumDimension,
              abs(frame.origin.y) <= LayoutPolicy.maximumDimension,
              frame.size.width >= TransformPolicy.minimumDimension,
              frame.size.height >= TransformPolicy.minimumDimension,
              frame.size.width <= LayoutPolicy.maximumDimension,
              frame.size.height <= LayoutPolicy.maximumDimension else {
            throw TransformError.invalidResult
        }
        return frame
    }

    private func validateOperation(_ operation: TransformOperation) throws {
        let delta: WorldVector
        switch operation {
        case .move(let value, _), .resize(_, let value, _): delta = value
        }
        guard delta.dx.isFinite, delta.dy.isFinite,
              abs(delta.dx) <= LayoutPolicy.maximumDimension,
              abs(delta.dy) <= LayoutPolicy.maximumDimension else {
            throw TransformError.invalidDelta
        }
    }

    private func propertyCommands(
        pageID: PageID,
        node: DocumentNode,
        frame: WorldRect,
        operation: TransformOperation
    ) throws -> [DocumentCommand] {
        let values: [(String, Double)]
        switch operation {
        case .move:
            values = [("layout.x", frame.origin.x), ("layout.y", frame.origin.y)]
        case .resize:
            values = [
                ("layout.x", frame.origin.x), ("layout.y", frame.origin.y),
                ("layout.width", frame.size.width), ("layout.height", frame.size.height),
            ]
        }
        return try values.map { key, value in
            guard let property = node.insertionProperty(key) else {
                throw TransformError.incompatibleGeometry
            }
            return .setProperty(SetPropertyCommand(
                pageID: pageID,
                nodeID: node.id,
                property: NodeProperty(
                    id: property.id,
                    key: property.key,
                    value: .number(value),
                    origin: .authored
                )
            ))
        }
    }
}

enum ContainerLayoutInspectorValue: Equatable, Sendable {
    case unavailable(String)
    case single(ContainerLayoutValue, PropertyOrigin, applicableCount: Int, skippedCount: Int)
    case mixed(applicableCount: Int, skippedCount: Int)
}

enum ContainerLayoutProvenance: String, Sendable {
    case pointer, keyboard, focusLoss = "focus-loss", picker, accessibility, automation
}

struct ContainerLayoutCommand: Sendable {
    let identity: GeometryInspectorOperationIdentity
    let orderedNodeIDs: [NodeID]
    let field: ContainerLayoutField
    let value: ContainerLayoutValue?
    let provenance: ContainerLayoutProvenance
    let cancelled: Bool
    var breakpoint: ResponsiveBreakpoint = .desktop
    var removesOverride = false
}

struct PreparedContainerLayoutEdit: Sendable {
    let identity: GeometryInspectorOperationIdentity
    let field: ContainerLayoutField
    let applicableNodeIDs: [NodeID]
    let skippedNodeIDs: [NodeID]
    let documentCommand: DocumentCommand
    let breakpoint: ResponsiveBreakpoint
    let removesOverride: Bool
}

enum ContainerLayoutError: Error, Equatable, LocalizedError, Sendable {
    case cancelled, staleDocument, staleRevision, staleRenderer, selectionMismatch
    case duplicateTarget, emptySelection, pageUnavailable, missingTarget
    case lockedTarget, hiddenTarget, unavailableTarget, invalidValue
    case noApplicableTargets, noChanges, revisionExhausted, lifecycleUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: "The container-layout draft was cancelled; committed layout is unchanged."
        case .staleDocument, .staleRevision, .staleRenderer, .selectionMismatch:
            "The container-layout edit is stale; reselect the container and try again."
        case .duplicateTarget: "The container-layout selection contains a duplicate object."
        case .emptySelection: "Select a Section, Stack, or Grid to edit layout."
        case .pageUnavailable, .missingTarget: "A selected container is no longer on the active page."
        case .lockedTarget: "Unlock the selected container before editing its layout."
        case .hiddenTarget: "Show the selected container before editing its layout."
        case .unavailableTarget: "The selected container is unavailable in the current scene."
        case .invalidValue: "Enter a supported finite container-layout value."
        case .noApplicableTargets: "The selection has no object that supports this layout control."
        case .noChanges: "The selected containers already use that layout value."
        case .revisionExhausted: "The document cannot accept another revision."
        case .lifecycleUnavailable(let reason): reason
        }
    }
}

struct ContainerLayoutCommandRegistry: Sendable {
    static let requirementIDs: Set<String> = Set((1...8).map { String(format: "SF-0502-%03d", $0) })
        .union((1...8).map { String(format: "SF-0503-%03d", $0) })
        .union((1...8).map { String(format: "SF-0506-%03d", $0) })

    static func supports(_ field: ContainerLayoutField, kind: NodeKind) -> Bool {
        switch (kind, field) {
        case (.section, .padding): true
        case (.stack, .padding), (.stack, .gap), (.stack, .axis), (.stack, .alignment): true
        case (.grid, .padding), (.grid, .gap), (.grid, .columns): true
        default: false
        }
    }

    static func defaultValue(for field: ContainerLayoutField, kind: NodeKind) -> ContainerLayoutValue? {
        switch (kind, field) {
        case (.section, .padding): .number(48)
        case (.stack, .padding), (.stack, .gap), (.grid, .padding), (.grid, .gap): .number(24)
        case (.stack, .axis): .axis(.vertical)
        case (.stack, .alignment): .alignment(.start)
        case (.grid, .columns): .number(2)
        default: nil
        }
    }

    static func value(_ propertyValue: PropertyValue, for field: ContainerLayoutField) -> ContainerLayoutValue? {
        switch (field, propertyValue) {
        case (.padding, .number(let value)), (.gap, .number(let value)), (.columns, .number(let value)):
            return .number(value)
        case (.axis, .string(let value)):
            return ContainerLayoutAxis(rawValue: value).map(ContainerLayoutValue.axis)
        case (.alignment, .string(let value)):
            return ContainerLayoutAlignment(rawValue: value).map(ContainerLayoutValue.alignment)
        default: return nil
        }
    }

    static func resolvedValue(_ field: ContainerLayoutField, node: DocumentNode) -> ContainerLayoutValue? {
        guard supports(field, kind: node.kind) else { return nil }
        switch field {
        case .padding, .gap, .columns:
            return node.insertionNumberProperty(field.propertyKey).map(ContainerLayoutValue.number)
        case .axis:
            return node.insertionStringProperty(field.propertyKey)
                .flatMap(ContainerLayoutAxis.init(rawValue:)).map(ContainerLayoutValue.axis)
        case .alignment:
            return node.insertionStringProperty(field.propertyKey)
                .flatMap(ContainerLayoutAlignment.init(rawValue:)).map(ContainerLayoutValue.alignment)
        }
    }

    func value(
        for field: ContainerLayoutField,
        in document: CanonicalDocument,
        context: TransformValidationContext,
        breakpoint: ResponsiveBreakpoint = .desktop
    ) -> ContainerLayoutInspectorValue {
        guard let page = document.pages.first(where: { $0.id == context.activePageID }) else {
            return .unavailable("The active page is unavailable.")
        }
        let selected = context.selectedNodeIDs.compactMap { id in page.nodes.first(where: { $0.id == id }) }
        let applicable = selected.filter { Self.supports(field, kind: $0.kind) }
        guard !applicable.isEmpty else {
            return .unavailable("The selection does not support \(field.title.lowercased()).")
        }
        let values = applicable.compactMap { node -> (ContainerLayoutValue, PropertyOrigin)? in
            ResponsiveContainerLayoutResolver.value(for: field, node: node, breakpoint: breakpoint)
                .map { ($0.0, $0.1) }
        }
        guard values.count == applicable.count, let first = values.first else {
            return .unavailable("The selected containers have invalid canonical layout state.")
        }
        if values.dropFirst().allSatisfy({ $0.0 == first.0 && $0.1 == first.1 }) {
            return .single(first.0, first.1, applicableCount: applicable.count, skippedCount: selected.count - applicable.count)
        }
        return .mixed(applicableCount: applicable.count, skippedCount: selected.count - applicable.count)
    }

    func prepare(
        _ command: ContainerLayoutCommand,
        in document: CanonicalDocument,
        context: TransformValidationContext,
        cancellation: TransformCancellation = .never
    ) throws -> PreparedContainerLayoutEdit {
        guard !command.cancelled, !cancellation.isCancelled() else { throw ContainerLayoutError.cancelled }
        guard context.isLifecycleAvailable else {
            throw ContainerLayoutError.lifecycleUnavailable(context.lifecycleDisabledReason ?? "Layout editing is unavailable during the current document operation.")
        }
        guard command.identity.documentID == document.id else { throw ContainerLayoutError.staleDocument }
        guard command.identity.revision == document.revision else { throw ContainerLayoutError.staleRevision }
        guard document.revision < UInt64.max else { throw ContainerLayoutError.revisionExhausted }
        guard command.identity.pageID == context.activePageID,
              let page = document.pages.first(where: { $0.id == context.activePageID }) else {
            throw ContainerLayoutError.pageUnavailable
        }
        guard command.identity.sceneID == context.currentSceneID,
              command.identity.rendererGeneration == context.rendererGeneration else {
            throw ContainerLayoutError.staleRenderer
        }
        guard !command.orderedNodeIDs.isEmpty else { throw ContainerLayoutError.emptySelection }
        guard Set(command.orderedNodeIDs).count == command.orderedNodeIDs.count else { throw ContainerLayoutError.duplicateTarget }
        guard command.orderedNodeIDs == context.selectedNodeIDs else { throw ContainerLayoutError.selectionMismatch }
        if let value = command.value { try Self.validate(value, field: command.field) }

        var applicable: [NodeID] = []
        var skipped: [NodeID] = []
        var mutations: [DocumentCommand] = []
        for id in command.orderedNodeIDs {
            guard !cancellation.isCancelled() else { throw ContainerLayoutError.cancelled }
            guard let node = page.nodes.first(where: { $0.id == id }) else { throw ContainerLayoutError.missingTarget }
            guard Self.supports(command.field, kind: node.kind) else { skipped.append(id); continue }
            guard !node.insertionBooleanProperty("locked") else { throw ContainerLayoutError.lockedTarget }
            guard !node.insertionBooleanProperty("hidden") else { throw ContainerLayoutError.hiddenTarget }
            guard context.availableNodeIDs.contains(id) else { throw ContainerLayoutError.unavailableTarget }
            guard let baseProperty = node.insertionProperty(command.field.propertyKey),
                  let defaultValue = Self.defaultValue(for: command.field, kind: node.kind) else {
                throw ContainerLayoutError.invalidValue
            }
            if command.breakpoint == .desktop {
                guard !command.removesOverride else { throw ContainerLayoutError.invalidValue }
                let nextValue = command.value ?? defaultValue
                let nextOrigin: PropertyOrigin = command.value == nil ? .defaulted : .authored
                if baseProperty.value == nextValue.propertyValue, baseProperty.origin == nextOrigin { continue }
                applicable.append(id)
                mutations.append(.setProperty(.init(pageID: page.id, nodeID: id,
                    property: .init(id: baseProperty.id, key: baseProperty.key,
                                    value: nextValue.propertyValue, origin: nextOrigin))))
            } else {
                let key = ResponsiveContainerLayoutResolver.key(command.field, breakpoint: command.breakpoint)
                if let property = node.insertionProperty(key) {
                    if command.removesOverride {
                        applicable.append(id)
                        mutations.append(.removeProperty(.init(pageID: page.id, nodeID: id, propertyID: property.id)))
                    } else if let value = command.value,
                              property.value != value.propertyValue || property.origin != .authored {
                        applicable.append(id)
                        mutations.append(.setProperty(.init(pageID: page.id, nodeID: id,
                            property: .init(id: property.id, key: property.key,
                                            value: value.propertyValue, origin: .authored))))
                    }
                } else if !command.removesOverride, let value = command.value {
                    applicable.append(id)
                    mutations.append(.setProperty(.init(pageID: page.id, nodeID: id,
                        property: .init(key: .init(rawValue: key), value: value.propertyValue, origin: .authored),
                        insertionIndex: node.properties.count)))
                }
            }
        }
        guard !applicable.isEmpty else {
            if skipped.count == command.orderedNodeIDs.count { throw ContainerLayoutError.noApplicableTargets }
            throw ContainerLayoutError.noChanges
        }
        let documentCommand = DocumentCommand.batch(mutations)
        guard CommandRegistry().availability(for: documentCommand, in: document).isEnabled else {
            throw ContainerLayoutError.invalidValue
        }
        return .init(identity: command.identity, field: command.field,
                     applicableNodeIDs: applicable, skippedNodeIDs: skipped,
                     documentCommand: documentCommand, breakpoint: command.breakpoint,
                     removesOverride: command.removesOverride)
    }

    static func validate(_ value: ContainerLayoutValue, field: ContainerLayoutField) throws {
        switch (field, value) {
        case (.padding, .number(let number)), (.gap, .number(let number)):
            guard number.isFinite, (0...10_000).contains(number) else { throw ContainerLayoutError.invalidValue }
        case (.columns, .number(let number)):
            guard number.isFinite, number.rounded(.towardZero) == number, (1...64).contains(number) else {
                throw ContainerLayoutError.invalidValue
            }
        case (.axis, .axis), (.alignment, .alignment): break
        default: throw ContainerLayoutError.invalidValue
        }
    }
}

enum ResponsiveVisibilityProvenance: String, Sendable {
    case pointer, keyboard, accessibility, automation
}

enum ResponsiveVisibilityInspectorValue: Equatable, Sendable {
    case unavailable(String)
    case single(Bool, PropertyOrigin, ResponsiveVisibilitySource, applicableCount: Int, skippedCount: Int)
    case mixed(applicableCount: Int, skippedCount: Int)
}

struct ResponsiveVisibilityCommand: Sendable {
    let identity: GeometryInspectorOperationIdentity
    let orderedNodeIDs: [NodeID]
    let breakpoint: ResponsiveBreakpoint
    let visible: Bool?
    let provenance: ResponsiveVisibilityProvenance
    let cancelled: Bool
}

struct PreparedResponsiveVisibilityEdit: Sendable {
    let applicableNodeIDs: [NodeID]
    let skippedNodeIDs: [NodeID]
    let documentCommand: DocumentCommand
}

enum ResponsiveVisibilityError: Error, Equatable, LocalizedError, Sendable {
    case cancelled, staleDocument, staleRevision, staleRenderer, selectionMismatch
    case duplicateTarget, emptySelection, pageUnavailable, missingTarget
    case lockedTarget, unavailableTarget, noApplicableTargets, noChanges
    case lifecycleUnavailable(String), revisionExhausted

    var errorDescription: String? {
        switch self {
        case .cancelled: "The visibility edit was cancelled; committed visibility is unchanged."
        case .staleDocument, .staleRevision, .staleRenderer, .selectionMismatch:
            "The visibility edit is stale; reselect the object and try again."
        case .duplicateTarget: "The visibility selection contains a duplicate object."
        case .emptySelection: "Select an object to edit breakpoint visibility."
        case .pageUnavailable, .missingTarget: "A selected object is no longer on the active page."
        case .lockedTarget: "Unlock the selected object before changing visibility."
        case .unavailableTarget: "The selected object is unavailable."
        case .noApplicableTargets: "The selection has no object that supports breakpoint visibility."
        case .noChanges: "The selected objects already use that visibility value."
        case .lifecycleUnavailable(let reason): reason
        case .revisionExhausted: "The document cannot accept another revision."
        }
    }
}

struct ResponsiveVisibilityCommandRegistry: Sendable {
    static let requirementIDs: Set<String> = Set((1...8).map { String(format: "SF-0603-%03d", $0) })

    func value(
        in document: CanonicalDocument,
        context: TransformValidationContext,
        breakpoint: ResponsiveBreakpoint
    ) -> ResponsiveVisibilityInspectorValue {
        guard let page = document.pages.first(where: { $0.id == context.activePageID }) else {
            return .unavailable("The active page is unavailable.")
        }
        let selected = context.selectedNodeIDs.compactMap { id in page.nodes.first(where: { $0.id == id }) }
        let applicable = selected.filter(ResponsiveVisibilityResolver.supports)
        guard !applicable.isEmpty else { return .unavailable("The selection does not support breakpoint visibility.") }
        let values = applicable.map { ResponsiveVisibilityResolver.value(for: $0, breakpoint: breakpoint) }
        guard let first = values.first else { return .unavailable("Visibility is unavailable.") }
        if values.dropFirst().allSatisfy({ $0.0 == first.0 && $0.1 == first.1 && $0.2 == first.2 }) {
            return .single(first.0, first.1, first.2, applicableCount: applicable.count,
                           skippedCount: selected.count - applicable.count)
        }
        return .mixed(applicableCount: applicable.count, skippedCount: selected.count - applicable.count)
    }

    func prepare(
        _ command: ResponsiveVisibilityCommand,
        in document: CanonicalDocument,
        context: TransformValidationContext
    ) throws -> PreparedResponsiveVisibilityEdit {
        guard !command.cancelled else { throw ResponsiveVisibilityError.cancelled }
        guard context.isLifecycleAvailable else {
            throw ResponsiveVisibilityError.lifecycleUnavailable(context.lifecycleDisabledReason ?? "Visibility editing is unavailable.")
        }
        guard command.identity.documentID == document.id else { throw ResponsiveVisibilityError.staleDocument }
        guard command.identity.revision == document.revision else { throw ResponsiveVisibilityError.staleRevision }
        guard document.revision < UInt64.max else { throw ResponsiveVisibilityError.revisionExhausted }
        guard command.identity.pageID == context.activePageID,
              let page = document.pages.first(where: { $0.id == context.activePageID }) else {
            throw ResponsiveVisibilityError.pageUnavailable
        }
        guard command.identity.sceneID == context.currentSceneID,
              command.identity.rendererGeneration == context.rendererGeneration else {
            throw ResponsiveVisibilityError.staleRenderer
        }
        guard !command.orderedNodeIDs.isEmpty else { throw ResponsiveVisibilityError.emptySelection }
        guard Set(command.orderedNodeIDs).count == command.orderedNodeIDs.count else { throw ResponsiveVisibilityError.duplicateTarget }
        guard command.orderedNodeIDs == context.selectedNodeIDs else { throw ResponsiveVisibilityError.selectionMismatch }
        var applicable: [NodeID] = [], skipped: [NodeID] = [], mutations: [DocumentCommand] = []
        for id in command.orderedNodeIDs {
            guard let node = page.nodes.first(where: { $0.id == id }) else { throw ResponsiveVisibilityError.missingTarget }
            guard ResponsiveVisibilityResolver.supports(node) else { skipped.append(id); continue }
            guard !node.insertionBooleanProperty("locked") else { throw ResponsiveVisibilityError.lockedTarget }
            guard context.availableNodeIDs.contains(id)
                    || !ResponsiveVisibilityResolver.isVisible(node, breakpoint: command.breakpoint) else {
                throw ResponsiveVisibilityError.unavailableTarget
            }
            if command.breakpoint == .desktop {
                guard let visible = command.visible,
                      let property = node.insertionProperty("hidden") else { throw ResponsiveVisibilityError.noChanges }
                let next = PropertyValue.boolean(!visible)
                guard property.value != next else { continue }
                applicable.append(id)
                mutations.append(.setProperty(.init(pageID: page.id, nodeID: id,
                    property: .init(id: property.id, key: property.key, value: next, origin: .authored))))
            } else {
                let key = ResponsiveVisibilityResolver.key(command.breakpoint)
                if let property = node.insertionProperty(key) {
                    if let visible = command.visible {
                        guard property.value != .boolean(visible) else { continue }
                        applicable.append(id)
                        mutations.append(.setProperty(.init(pageID: page.id, nodeID: id,
                            property: .init(id: property.id, key: property.key,
                                            value: .boolean(visible), origin: .authored))))
                    } else {
                        applicable.append(id)
                        mutations.append(.removeProperty(.init(pageID: page.id, nodeID: id, propertyID: property.id)))
                    }
                } else if let visible = command.visible {
                    applicable.append(id)
                    mutations.append(.setProperty(.init(pageID: page.id, nodeID: id,
                        property: .init(key: .init(rawValue: key), value: .boolean(visible), origin: .authored),
                        insertionIndex: node.properties.count)))
                }
            }
        }
        guard !applicable.isEmpty else {
            if skipped.count == command.orderedNodeIDs.count { throw ResponsiveVisibilityError.noApplicableTargets }
            throw ResponsiveVisibilityError.noChanges
        }
        let documentCommand = DocumentCommand.batch(mutations)
        guard CommandRegistry().availability(for: documentCommand, in: document).isEnabled else {
            throw ResponsiveVisibilityError.unavailableTarget
        }
        return .init(applicableNodeIDs: applicable, skippedNodeIDs: skipped, documentCommand: documentCommand)
    }
}

enum ResponsiveVisibilityDiagnosticResult: String, Codable, Sendable {
    case success, failure, cancelled, stale
}

struct ResponsiveVisibilityDiagnosticRecord: Codable, Equatable, Sendable {
    let requirementIDs: [String]
    let operationType: String
    let provenance: String
    let sanitizedIdentifiers: [String]
    let durationMilliseconds: Double
    let parentRevision: UInt64
    let resultRevision: UInt64?
    let affectedObjectCount: Int
    let result: ResponsiveVisibilityDiagnosticResult
    let failureCategory: String?
}

actor ResponsiveVisibilityDiagnostics {
    private var buffer: BoundedDiagnosticBuffer<ResponsiveVisibilityDiagnosticRecord>

    init(capacity: Int = DiagnosticRetentionPolicy.defaultCapacity) {
        buffer = BoundedDiagnosticBuffer(capacity: capacity)
    }

    func append(_ record: ResponsiveVisibilityDiagnosticRecord) { buffer.append(record) }
    func snapshot() -> [ResponsiveVisibilityDiagnosticRecord] { buffer.snapshot() }
    func droppedRecordCount() -> UInt64 { buffer.droppedRecordCount }
}

enum ResponsiveVisibilityDiagnosticFactory {
    static func make(
        command: ResponsiveVisibilityCommand,
        durationMilliseconds: Double,
        resultRevision: UInt64?,
        result: ResponsiveVisibilityDiagnosticResult,
        failure: ResponsiveVisibilityError?
    ) -> ResponsiveVisibilityDiagnosticRecord {
        ResponsiveVisibilityDiagnosticRecord(
            requirementIDs: ResponsiveVisibilityCommandRegistry.requirementIDs.sorted(),
            operationType: command.visible == nil ? "responsive-visibility.reset" : "responsive-visibility.set",
            provenance: command.provenance.rawValue,
            sanitizedIdentifiers: command.orderedNodeIDs.map {
                DiagnosticStableIdentifier.sanitize($0.description, domain: .responsiveVisibility, kind: "node")
            },
            durationMilliseconds: max(0, durationMilliseconds),
            parentRevision: command.identity.revision,
            resultRevision: resultRevision,
            affectedObjectCount: command.orderedNodeIDs.count,
            result: result,
            failureCategory: failure.map(Self.failureCategory)
        )
    }

    private static func failureCategory(_ error: ResponsiveVisibilityError) -> String {
        switch error {
        case .cancelled: "cancelled"
        case .staleDocument, .staleRevision, .staleRenderer, .selectionMismatch: "stale-identity"
        case .duplicateTarget, .emptySelection, .pageUnavailable, .missingTarget: "invalid-target"
        case .lockedTarget, .unavailableTarget: "unavailable-target"
        case .noApplicableTargets: "no-applicable-target"
        case .noChanges: "no-change"
        case .lifecycleUnavailable: "lifecycle-unavailable"
        case .revisionExhausted: "revision-exhausted"
        }
    }
}

enum ContainerLayoutDiagnosticResult: String, Codable, Sendable {
    case success, failure, cancelled, stale
}

struct ContainerLayoutDiagnosticRecord: Codable, Equatable, Sendable {
    let requirementIDs: [String]
    let operationType: String
    let provenance: String
    let sanitizedIdentifiers: [String]
    let durationMilliseconds: Double
    let parentRevision: UInt64
    let resultRevision: UInt64?
    let affectedObjectCount: Int
    let result: ContainerLayoutDiagnosticResult
    let failureCategory: String?
}

actor ContainerLayoutDiagnostics {
    private var buffer: BoundedDiagnosticBuffer<ContainerLayoutDiagnosticRecord>

    init(capacity: Int = DiagnosticRetentionPolicy.defaultCapacity) {
        buffer = BoundedDiagnosticBuffer(capacity: capacity)
    }

    func append(_ record: ContainerLayoutDiagnosticRecord) { buffer.append(record) }
    func snapshot() -> [ContainerLayoutDiagnosticRecord] { buffer.snapshot() }
    func droppedRecordCount() -> UInt64 { buffer.droppedRecordCount }
}

enum ContainerLayoutDiagnosticFactory {
    static func make(
        command: ContainerLayoutCommand,
        durationMilliseconds: Double,
        resultRevision: UInt64?,
        result: ContainerLayoutDiagnosticResult,
        failure: ContainerLayoutError?
    ) -> ContainerLayoutDiagnosticRecord {
        ContainerLayoutDiagnosticRecord(
            requirementIDs: ContainerLayoutCommandRegistry.requirementIDs.sorted(),
            operationType: "container-layout.\(command.field.rawValue)",
            provenance: command.provenance.rawValue,
            sanitizedIdentifiers: command.orderedNodeIDs.map {
                DiagnosticStableIdentifier.sanitize(
                    $0.description,
                    domain: .containerLayout,
                    kind: "node"
                )
            },
            durationMilliseconds: max(0, durationMilliseconds),
            parentRevision: command.identity.revision,
            resultRevision: resultRevision,
            affectedObjectCount: command.orderedNodeIDs.count,
            result: result,
            failureCategory: failure.map(Self.failureCategory)
        )
    }

    private static func failureCategory(_ error: ContainerLayoutError) -> String {
        switch error {
        case .cancelled: "cancelled"
        case .staleDocument, .staleRevision, .staleRenderer, .selectionMismatch: "stale-identity"
        case .duplicateTarget, .emptySelection, .pageUnavailable, .missingTarget: "invalid-target"
        case .lockedTarget, .hiddenTarget, .unavailableTarget: "unavailable-target"
        case .invalidValue: "invalid-value"
        case .noApplicableTargets: "no-applicable-target"
        case .noChanges: "no-change"
        case .revisionExhausted: "revision-exhausted"
        case .lifecycleUnavailable: "lifecycle-unavailable"
        }
    }
}

struct TransformPreview: Equatable, Sendable {
    let identity: TransformOperationIdentity
    let operation: TransformOperation
    let geometries: [TransformGeometry]
}

enum TransformSessionPhase: Equatable, Sendable {
    case inactive
    case drafting(TransformOperationIdentity)
    case previewing(TransformPreview)
    case committing(TransformPreview)
    case cancelled
    case failed(TransformError)
}

struct TransformSession: Equatable, Sendable {
    private(set) var generation: UInt64 = 0
    private(set) var phase: TransformSessionPhase = .inactive

    mutating func begin(
        documentID: DocumentID,
        pageID: PageID,
        revision: UInt64,
        sceneID: CanvasViewportSceneID,
        rendererGeneration: UInt64
    ) -> TransformOperationIdentity {
        generation &+= 1
        let identity = TransformOperationIdentity(
            sessionID: TransformSessionID(),
            documentID: documentID,
            pageID: pageID,
            revision: revision,
            sceneID: sceneID,
            rendererGeneration: rendererGeneration
        )
        phase = .drafting(identity)
        return identity
    }

    mutating func preview(_ value: TransformPreview) {
        guard currentIdentity == value.identity else { return }
        phase = .previewing(value)
    }

    mutating func beginCommit(_ value: TransformPreview) {
        guard currentIdentity == value.identity else { return }
        phase = .committing(value)
    }

    mutating func complete() {
        phase = .inactive
    }

    mutating func deactivate() {
        generation &+= 1
        phase = .inactive
    }

    mutating func cancel() {
        generation &+= 1
        phase = .cancelled
    }

    mutating func fail(_ error: TransformError) {
        phase = .failed(error)
    }

    var currentIdentity: TransformOperationIdentity? {
        switch phase {
        case .drafting(let identity): identity
        case .previewing(let preview), .committing(let preview): preview.identity
        case .inactive, .cancelled, .failed: nil
        }
    }
}

enum TransformOverlayPlanner {
    static func overlays(
        selection: SelectionState,
        renderPlan: CanvasRenderPlan,
        preview: TransformPreview?,
        handleWorldSize: Double
    ) -> [CanvasEditorOverlay] {
        let previewByID = Dictionary(
            uniqueKeysWithValues: (preview?.geometries ?? []).map { ($0.nodeID, $0.preview) }
        )
        var result = selection.orderedIDs.compactMap { id -> CanvasEditorOverlay? in
            guard let object = renderPlan.authoredObjects.first(where: { $0.id == id }) else {
                return nil
            }
            // Transform chrome is editor-only presentation, but it must
            // still describe the same visible authored intersection as the
            // raster. A Desktop-positioned node can remain canonically
            // selected after a narrower preset without drawing a ghost
            // outline over the pasteboard.
            guard let frame = clipped(previewByID[id] ?? object.frame, to: renderPlan.viewport.contentBounds) else {
                return nil
            }
            return CanvasEditorOverlay(
                id: CanvasOverlayID(derivedUUID(namespace: id.rawValue, label: "preview")),
                objectID: id,
                frame: frame,
                kind: preview == nil ? "transform-selection" : "transform-preview"
            )
        }
        guard selection.count == 1,
              let primaryID = selection.primaryID,
              let object = renderPlan.authoredObjects.first(where: { $0.id == primaryID }) else {
            return result
        }
        let frame = previewByID[primaryID] ?? object.frame
        for handle in TransformHandle.allCases {
            let point = handlePoint(handle, frame: frame)
            let handleFrame = WorldRect(
                origin: WorldPoint(
                    x: point.x - handleWorldSize / 2,
                    y: point.y - handleWorldSize / 2
                ),
                size: WorldSize(width: handleWorldSize, height: handleWorldSize)
            )
            // Do not create a clipped/partial handle at the artboard edge:
            // it would imply that a non-visible region is directly
            // transformable. Keep only fully visible affordances.
            guard contains(renderPlan.viewport.contentBounds, handleFrame) else { continue }
            result.append(CanvasEditorOverlay(
                id: CanvasOverlayID(derivedUUID(namespace: primaryID.rawValue, label: handle.rawValue)),
                objectID: primaryID,
                frame: handleFrame,
                kind: "transform-handle-\(handle.rawValue)"
            ))
        }
        return result
    }

    private static func clipped(_ frame: WorldRect, to clip: WorldRect) -> WorldRect? {
        let minX = max(frame.minX, clip.minX)
        let minY = max(frame.minY, clip.minY)
        let maxX = min(frame.maxX, clip.maxX)
        let maxY = min(frame.maxY, clip.maxY)
        guard maxX > minX, maxY > minY else { return nil }
        return WorldRect(
            origin: WorldPoint(x: minX, y: minY),
            size: WorldSize(width: maxX - minX, height: maxY - minY)
        )
    }

    private static func contains(_ outer: WorldRect, _ inner: WorldRect) -> Bool {
        inner.minX >= outer.minX && inner.maxX <= outer.maxX &&
            inner.minY >= outer.minY && inner.maxY <= outer.maxY
    }

    static func hitHandle(
        at point: WorldPoint,
        frame: WorldRect,
        worldRadius: Double
    ) -> TransformHandle? {
        TransformHandle.allCases.first { handle in
            let candidate = handlePoint(handle, frame: frame)
            return abs(candidate.x - point.x) <= worldRadius
                && abs(candidate.y - point.y) <= worldRadius
        }
    }

    private static func handlePoint(_ handle: TransformHandle, frame: WorldRect) -> WorldPoint {
        let centerX = (frame.minX + frame.maxX) / 2
        let centerY = (frame.minY + frame.maxY) / 2
        return switch handle {
        case .topLeft: WorldPoint(x: frame.minX, y: frame.minY)
        case .top: WorldPoint(x: centerX, y: frame.minY)
        case .topRight: WorldPoint(x: frame.maxX, y: frame.minY)
        case .right: WorldPoint(x: frame.maxX, y: centerY)
        case .bottomRight: WorldPoint(x: frame.maxX, y: frame.maxY)
        case .bottom: WorldPoint(x: centerX, y: frame.maxY)
        case .bottomLeft: WorldPoint(x: frame.minX, y: frame.maxY)
        case .left: WorldPoint(x: frame.minX, y: centerY)
        }
    }

    private static func derivedUUID(namespace: UUID, label: String) -> UUID {
        var data = Data(namespace.uuidString.lowercased().utf8)
        data.append(Data(("transform-overlay:" + label).utf8))
        var bytes = Array(SHA256.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

enum TransformDiagnosticResult: String, Codable, Sendable {
    case success, failure, cancelled, stale
}

struct TransformDiagnosticRecord: Codable, Equatable, Sendable {
    let requirementIDs: [String]
    let operationType: String
    let provenance: TransformProvenance
    let sanitizedIdentifiers: [String]
    let durationMilliseconds: Double
    let parentRevision: UInt64
    let resultRevision: UInt64?
    let affectedObjectCount: Int
    let result: TransformDiagnosticResult
    let failureCategory: String?
}

actor TransformDiagnostics {
    private var buffer: BoundedDiagnosticBuffer<TransformDiagnosticRecord>

    init(capacity: Int = DiagnosticRetentionPolicy.defaultCapacity) {
        buffer = BoundedDiagnosticBuffer(capacity: capacity)
    }

    func append(_ record: TransformDiagnosticRecord) { buffer.append(record) }
    func snapshot() -> [TransformDiagnosticRecord] { buffer.snapshot() }
    func droppedRecordCount() -> UInt64 { buffer.droppedRecordCount }
}

enum TransformDiagnosticFactory {
    static func make(
        command: GeometryTransformCommand,
        durationMilliseconds: Double,
        resultRevision: UInt64?,
        result: TransformDiagnosticResult,
        failure: TransformError?
    ) -> TransformDiagnosticRecord {
        TransformDiagnosticRecord(
            requirementIDs: TransformCommandRegistry.requirementIDs.sorted(),
            operationType: command.operation.name,
            provenance: command.provenance,
            sanitizedIdentifiers: command.orderedNodeIDs.map(sanitize),
            durationMilliseconds: max(0, durationMilliseconds),
            parentRevision: command.identity.revision,
            resultRevision: resultRevision,
            affectedObjectCount: command.orderedNodeIDs.count,
            result: result,
            failureCategory: failure.map(\.diagnosticCategory)
        )
    }

    private static func sanitize(_ id: NodeID) -> String {
        DiagnosticStableIdentifier.sanitize(
            id.description,
            domain: .transform,
            kind: "node"
        )
    }
}

// MARK: - Fixed geometry Inspector diagnostics

/// Kept distinct from gesture diagnostics so a direct Inspector edit cannot
/// masquerade as a move or resize in support data. Records intentionally carry
/// only stable-ID digests and typed outcome categories.
enum GeometryInspectorDiagnosticResult: String, Codable, Sendable {
    case success, failure, cancelled, stale
}

struct GeometryInspectorDiagnosticRecord: Codable, Equatable, Sendable {
    let requirementIDs: [String]
    let operationType: String
    let provenance: GeometryInspectorProvenance
    let sanitizedIdentifiers: [String]
    let durationMilliseconds: Double
    let parentRevision: UInt64
    let resultRevision: UInt64?
    let affectedObjectCount: Int
    let result: GeometryInspectorDiagnosticResult
    let failureCategory: String?
}

actor GeometryInspectorDiagnostics {
    private var buffer: BoundedDiagnosticBuffer<GeometryInspectorDiagnosticRecord>

    init(capacity: Int = DiagnosticRetentionPolicy.defaultCapacity) {
        buffer = BoundedDiagnosticBuffer(capacity: capacity)
    }

    func append(_ record: GeometryInspectorDiagnosticRecord) { buffer.append(record) }
    func snapshot() -> [GeometryInspectorDiagnosticRecord] { buffer.snapshot() }
    func droppedRecordCount() -> UInt64 { buffer.droppedRecordCount }
}

enum GeometryInspectorDiagnosticFactory {
    static func make(
        command: GeometryInspectorCommand,
        durationMilliseconds: Double,
        resultRevision: UInt64?,
        result: GeometryInspectorDiagnosticResult,
        failure: GeometryInspectorError?
    ) -> GeometryInspectorDiagnosticRecord {
        let requirements = command.breakpoint == .desktop && !command.removesOverride
            ? GeometryInspectorCommandRegistry.requirementIDs
            : GeometryInspectorCommandRegistry.responsiveRequirementIDs
        return GeometryInspectorDiagnosticRecord(
            requirementIDs: requirements.sorted(),
            operationType: "geometry-inspector.\(command.field.rawValue)",
            provenance: command.provenance,
            sanitizedIdentifiers: command.orderedNodeIDs.map(sanitize),
            durationMilliseconds: max(0, durationMilliseconds),
            parentRevision: command.identity.revision,
            resultRevision: resultRevision,
            affectedObjectCount: command.orderedNodeIDs.count,
            result: result,
            failureCategory: failure.map(\.diagnosticCategory)
        )
    }

    private static func sanitize(_ id: NodeID) -> String {
        DiagnosticStableIdentifier.sanitize(
            id.description,
            domain: .geometryInspector,
            kind: "node"
        )
    }
}

private extension TransformError {
    var diagnosticCategory: String {
        switch self {
        case .lifecycleUnavailable: "lifecycle-unavailable"
        case .emptySelection: "empty-selection"
        case .duplicateTarget: "duplicate-target"
        case .staleDocument: "stale-document"
        case .staleRevision: "stale-revision"
        case .revisionExhausted: "revision-exhausted"
        case .staleRenderer: "stale-renderer"
        case .pageUnavailable: "page-unavailable"
        case .crossPageTarget: "cross-page-target"
        case .selectionMismatch: "selection-mismatch"
        case .missingTarget: "missing-target"
        case .lockedTarget: "locked-target"
        case .hiddenTarget: "hidden-target"
        case .unavailableTarget: "unavailable-target"
        case .incompatibleGeometry: "incompatible-geometry"
        case .incompatibleMultipleResize: "incompatible-multiple-resize"
        case .invalidDelta: "invalid-delta"
        case .invalidResult: "invalid-result"
        case .cancelled: "cancelled"
        }
    }
}

private extension GeometryInspectorError {
    var diagnosticCategory: String {
        switch self {
        case .lifecycleUnavailable: "lifecycle-unavailable"
        case .emptySelection: "empty-selection"
        case .duplicateTarget: "duplicate-target"
        case .staleDocument: "stale-document"
        case .staleRevision: "stale-revision"
        case .staleRenderer: "stale-renderer"
        case .pageUnavailable: "page-unavailable"
        case .selectionMismatch: "selection-mismatch"
        case .revisionExhausted: "revision-exhausted"
        case .missingTarget: "missing-target"
        case .lockedTarget: "locked-target"
        case .hiddenTarget: "hidden-target"
        case .unavailableTarget: "unavailable-target"
        case .noApplicableTargets: "no-applicable-targets"
        case .invalidValue: "invalid-value"
        case .cancelled: "cancelled"
        }
    }
}
// MARK: - Design inspector presentation

/// Editor-only feedback derived from the current selection. Keeping this
/// policy pure makes it impossible for a previous edit's mixed-target result
/// to be represented as feedback for a replacement selection.
enum DesignInspectorSelectionPresentation {
    static func contextAnnouncement(selectionCount: Int) -> String {
        selectionCount == 0
            ? "Design Inspector requires a selection."
            : "Design Inspector updated for current selection."
    }
}
