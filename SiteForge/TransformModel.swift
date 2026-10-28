import CryptoKit
import Foundation

// SF-0403-001...008 — bounded deterministic move/resize geometry transforms.

// SF-0508-001...008 — bounded solid fill and opacity authoring.  RGBA is
// deliberately stored as four finite canonical numeric properties rather than
// a presentation string, so locale/display color notation never becomes part
// of the document format.
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
    /// An omitted enabled flag resolves to `true` for an existing legacy or
    /// authored shadow. Explicit false retains the complete typed shadow for
    /// reversible disable/enable without flattening its intent.
    let shadowEnabled: Bool?
    /// Content padding is intentionally uniform in this bounded slice. `nil`
    /// means the explicit default (zero), retaining omitted/defaulted/authored
    /// provenance without introducing per-edge state.
    let padding: Double?
    /// `nil` resolves to visible overflow; explicit false remains authored so
    /// reset can faithfully restore default behavior.
    let clipsContent: Bool?

    init(
        border: CanonicalBorder?,
        cornerRadius: Double?,
        shadow: CanonicalShadow?,
        shadowEnabled: Bool? = nil,
        padding: Double? = nil,
        clipsContent: Bool? = nil
    ) {
        self.border = border
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.shadowEnabled = shadowEnabled
        self.padding = padding
        self.clipsContent = clipsContent
    }

    var isValid: Bool {
        (border?.isValid ?? true)
            && (cornerRadius.map { $0.isFinite && (0...10_000).contains($0) } ?? true)
            && (shadow?.isValid ?? true)
            && (shadow != nil || shadowEnabled == nil)
            && (padding.map { $0.isFinite && (0...10_000).contains($0) } ?? true)
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
    case shadowEnabled(Bool?)
    case padding(Double?)
    case clipsContent(Bool?)
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
        case .invalidValue: "Enter a finite border, radius, padding, or shadow value within the supported range."
        case .unavailable(let reason): reason
        case .noApplicableTargets: "The selection has no object that supports border, radius, or shadow."
        case .noChanges: "The appearance already has that value."
        }
    }
}

struct DesignBoxStyleCommandRegistry: Sendable {
    static let requirementIDs: Set<String> = Set((1...8).map { String(format: "SF-0506-%03d", $0) })
    static let applicableKinds: Set<NodeKind> = [.frame, .section, .stack, .grid, .button]
    static let contentBoxKinds: Set<NodeKind> = [.frame, .section]
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
        let shadowEnabled: Bool? = node.insertionProperty(namespace + "shadow.enabled").flatMap {
            if case .boolean(let value) = $0.value { return value }
            return nil
        }
        let padding = number("padding.uniform").flatMap { $0.isFinite && (0...10_000).contains($0) ? $0 : nil }
        let clipsContent: Bool? = node.insertionProperty(namespace + "clip.content").flatMap {
            if case .boolean(let value) = $0.value { return value }
            return nil
        }
        return CanonicalBoxStyle(border: border, cornerRadius: radius, shadow: shadow, shadowEnabled: shadowEnabled,
                                 padding: padding, clipsContent: clipsContent)
    }

    /// Property decoding is intentionally strict at the mutation/output
    /// boundary.  A malformed persisted content-box value is not quietly
    /// treated as an omitted default, which would make a later edit destroy
    /// the evidence needed for recovery.
    static func hasWellFormedContentBoxProperties(_ node: DocumentNode) -> Bool {
        guard contentBoxKinds.contains(node.kind) else { return true }
        let contentKeys = [namespace + "padding.uniform", namespace + "clip.content"]
        guard contentKeys.allSatisfy({ key in node.properties.filter { $0.key.rawValue == key }.count <= 1 }) else {
            return false
        }
        if let property = node.insertionProperty(namespace + "padding.uniform") {
            guard case .number(let value) = property.value,
                  value.isFinite, (0...10_000).contains(value) else { return false }
        }
        if let property = node.insertionProperty(namespace + "clip.content") {
            guard case .boolean = property.value else { return false }
        }
        return true
    }

    static func selectionValue(nodes: [DocumentNode]) -> DesignBoxStyleValue {
        guard !nodes.isEmpty else { return .unavailable("Select a Frame, Section, Stack, or Grid to edit border, radius, and shadow.") }
        let applicable = nodes.filter { applicableKinds.contains($0.kind) }
        guard !applicable.isEmpty else { return .unavailable("The selected objects do not support box appearance.") }
        guard applicable.allSatisfy(hasWellFormedContentBoxProperties) else {
            return .unavailable("A selected object has invalid persisted content-box data and cannot be edited safely.")
        }
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
            guard Self.hasWellFormedContentBoxProperties(node) else { throw DesignBoxStyleError.invalidValue }
            guard Self.supports(command.edit, kind: node.kind) else {
                skipped.append(id); reasons[id] = "This object kind does not support the selected box control."; continue
            }
            switch command.edit {
            case .border(let value):
                if let value, !value.isValid { throw DesignBoxStyleError.invalidValue }
                let border: CanonicalBorder?
                if LocalColorTokenBinding.id(for: node, target: .border) != nil {
                    guard let value, let existing = style.border else {
                        throw DesignBoxStyleError.unavailable("Unbind the border token before removing its border.")
                    }
                    border = .init(color: existing.color, width: value.width, style: value.style)
                } else { border = value }
                style = .init(border: border, cornerRadius: style.cornerRadius, shadow: style.shadow, shadowEnabled: style.shadowEnabled,
                              padding: style.padding, clipsContent: style.clipsContent)
            case .cornerRadius(let value):
                if let value, (!value.isFinite || !(0...10_000).contains(value)) { throw DesignBoxStyleError.invalidValue }
                style = .init(border: style.border, cornerRadius: value, shadow: style.shadow, shadowEnabled: style.shadowEnabled,
                              padding: style.padding, clipsContent: style.clipsContent)
            case .shadow(let value):
                if let value, !value.isValid { throw DesignBoxStyleError.invalidValue }
                let shadow: CanonicalShadow?
                if LocalColorTokenBinding.id(for: node, target: .outerShadow) != nil {
                    guard let value, let existing = style.shadow else {
                        throw DesignBoxStyleError.unavailable("Unbind the outer-shadow token before removing its shadow.")
                    }
                    shadow = .init(color: existing.color, offsetX: value.offsetX,
                        offsetY: value.offsetY, blur: value.blur, spread: value.spread)
                } else { shadow = value }
                style = .init(border: style.border, cornerRadius: style.cornerRadius, shadow: shadow,
                              shadowEnabled: value == nil ? nil : style.shadowEnabled,
                              padding: style.padding, clipsContent: style.clipsContent)
            case .shadowEnabled(let value):
                guard style.shadow != nil else { throw DesignBoxStyleError.unavailable("Add an outer shadow before changing its enabled state.") }
                style = .init(border: style.border, cornerRadius: style.cornerRadius, shadow: style.shadow,
                              shadowEnabled: value, padding: style.padding, clipsContent: style.clipsContent)
            case .padding(let value):
                if let value, (!value.isFinite || !(0...10_000).contains(value)) { throw DesignBoxStyleError.invalidValue }
                style = .init(border: style.border, cornerRadius: style.cornerRadius, shadow: style.shadow, shadowEnabled: style.shadowEnabled,
                              padding: value, clipsContent: style.clipsContent)
            case .clipsContent(let value):
                style = .init(border: style.border, cornerRadius: style.cornerRadius, shadow: style.shadow, shadowEnabled: style.shadowEnabled,
                              padding: style.padding, clipsContent: value)
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
        let availability = CommandRegistry().availability(for: batch, in: document)
        guard availability.isEnabled else {
            throw DesignBoxStyleError.unavailable(availability.disabledReason ?? "The document no longer accepts this appearance change.")
        }
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
        if let padding = style.padding { result[namespace + "padding.uniform"] = .number(padding) }
        if let clipsContent = style.clipsContent { result[namespace + "clip.content"] = .boolean(clipsContent) }
        if let shadow = style.shadow {
            result[namespace + "shadow.offsetX"] = .number(shadow.offsetX)
            result[namespace + "shadow.offsetY"] = .number(shadow.offsetY)
            result[namespace + "shadow.blur"] = .number(shadow.blur)
            result[namespace + "shadow.spread"] = .number(shadow.spread)
            set(shadow.color, prefix: namespace + "shadow.color", into: &result)
            if let enabled = style.shadowEnabled { result[namespace + "shadow.enabled"] = .boolean(enabled) }
        }
        return result
    }

    private static func set(_ color: CanonicalSolidColor, prefix: String, into values: inout [String: PropertyValue]) {
        values[prefix + ".red"] = .number(color.red); values[prefix + ".green"] = .number(color.green)
        values[prefix + ".blue"] = .number(color.blue); values[prefix + ".alpha"] = .number(color.alpha)
    }

    static func supports(_ edit: DesignBoxStyleEdit, kind: NodeKind) -> Bool {
        switch edit {
        case .padding, .clipsContent: contentBoxKinds.contains(kind)
        case .shadowEnabled: contentBoxKinds.contains(kind)
        case .border, .cornerRadius, .shadow: applicableKinds.contains(kind)
        }
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
    case foreground(CanonicalSolidColor?)
    case family(String?)
    case fontFace(family: String, weight: CanonicalFontWeight)
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
        case .noApplicableTargets: "The selection has no Text, Button, or Link object that supports typography."
        case .noChanges: "Typography already has that value."
        }
    }
}

struct TypographyCommandRegistry: Sendable {
    static let requirementIDs = Set((1...8).map { String(format: "SF-0507-%03d", $0) })
    static let namespace = CanonicalTypography.namespace

    static func resolvedTypography(for node: DocumentNode, viewportWidth: Double? = nil) -> CanonicalTypography? {
        guard let fixed = CanonicalTypography.resolved(for: node) else { return nil }
        guard let viewportWidth else { return fixed }
        let size = CanonicalFluidValueCodec.resolved(.fontSize, node: node, viewportWidth: viewportWidth)
            ?? fixed.size
        let lineHeight = CanonicalFluidValueCodec.resolved(.lineHeight, node: node, viewportWidth: viewportWidth)
            ?? fixed.lineHeight
        let resolved = CanonicalTypography(
            family: fixed.family, weight: fixed.weight, size: size,
            lineHeight: lineHeight, tracking: fixed.tracking, alignment: fixed.alignment
        )
        return resolved.isValid ? resolved : nil
    }

    static func selectionValue(nodes: [DocumentNode], viewportWidth: Double? = nil) -> TypographyInspectorValue {
        guard !nodes.isEmpty else { return .unavailable("Select Text, Button, or Link to edit typography.") }
        let applicable = nodes.filter { $0.kind.isTextual }
        guard !applicable.isEmpty else { return .unavailable("Typography applies only to Text, Button, or Link.") }
        let values = applicable.compactMap { resolvedTypography(for: $0, viewportWidth: viewportWidth) }
        guard values.count == applicable.count, let first = values.first,
              values.dropFirst().allSatisfy({ $0 == first }) else {
            return .mixed(applicableCount: applicable.count, skippedCount: nodes.count - applicable.count)
        }
        let origin: PropertyOrigin = applicable.flatMap(\.properties).contains {
            $0.origin == .authored && ($0.key.rawValue.hasPrefix(namespace)
                || (viewportWidth != nil && [CanonicalFluidValueCodec.key(.fontSize),
                    CanonicalFluidValueCodec.key(.lineHeight)].contains($0.key.rawValue)))
        } ? .authored : .defaulted
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
            guard node.kind.isTextual, var style = Self.resolvedTypography(for: node) else {
                skipped.append(id); reasons[id] = "This object kind does not support typography."; continue
            }
            if case .fontFace(let family, let weight) = command.edit {
                let next = CanonicalTypography(family: family, weight: weight, size: style.size,
                    lineHeight: style.lineHeight, tracking: style.tracking, alignment: style.alignment)
                guard next.isValid else { throw TypographyCommandError.invalidValue }
                applicable.append(id)
                // One intent, one transaction: no intermediate family carrying
                // an unavailable old weight. Existing properties retain IDs.
                for (suffix, value) in [("family", PropertyValue.string(family)), ("weight", .string(weight.rawValue))] {
                    let key = Self.namespace + suffix
                    let previous = node.insertionProperty(key)
                    if previous?.value == value && previous?.origin == .authored { continue }
                    changes.append(.setProperty(.init(pageID: page.id, nodeID: id,
                        property: .init(id: previous?.id ?? PropertyID(), key: .init(rawValue: key),
                            value: value, origin: .authored))))
                }
                continue
            }
            if case .reset = command.edit {
                applicable.append(id)
                changes.append(contentsOf: node.properties
                    .filter { $0.key.rawValue.hasPrefix(Self.namespace) }
                    .map { .removeProperty(.init(pageID: page.id, nodeID: id, propertyID: $0.id)) })
                if let binding = node.insertionProperty(LocalColorTokenBinding.key(for: .textForeground)) {
                    changes.append(.removeProperty(.init(pageID: page.id, nodeID: id, propertyID: binding.id)))
                }
                continue
            }
            if case .foreground(let color) = command.edit {
                guard LocalColorTokenBinding.id(for: node, target: .textForeground) == nil else {
                    throw TypographyCommandError.unavailable("Unbind the text color token before editing its literal fallback.")
                }
                if let color, !color.isValid { throw TypographyCommandError.invalidValue }
                applicable.append(id)
                for channel in CanonicalTextForeground.channels {
                    let key = CanonicalTextForeground.prefix + channel
                    let old = node.insertionProperty(key)
                    if let color, let value = CanonicalTextForeground.values(color).first(where: { $0.0 == key })?.1 {
                        if old?.value != value || old?.origin != .authored {
                            changes.append(.setProperty(.init(pageID: page.id, nodeID: id, property: .init(
                                id: old?.id ?? PropertyID(), key: .init(rawValue: key), value: value, origin: .authored))))
                        }
                    } else if let old {
                        changes.append(.removeProperty(.init(pageID: page.id, nodeID: id, propertyID: old.id)))
                    }
                }
                continue
            }
            let key: String
            let value: PropertyValue?
            switch command.edit {
            case .reset:
                preconditionFailure("Reset is handled before scalar typography edits.")
            case .foreground:
                preconditionFailure("Foreground is handled before scalar typography edits.")
            case .fontFace:
                preconditionFailure("Font family and weight are handled atomically before scalar edits.")
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
    private static let supportedKinds: Set<NodeKind> = [.frame, .section, .stack, .grid, .button]

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

/// Discoverability only: page backgrounds remain fills on the existing single
/// geometry-less ownership Root. Never guess between multiple authored roots.
enum PageBackgroundPolicy {
    static func root(in page: DocumentPage?) -> DocumentNode? {
        guard let page, page.role != .componentDefinition, page.rootNodeIDs.count == 1,
              let root = page.nodes.first(where: { $0.id == page.rootNodeIDs[0] }),
              root.parent == .page(page.id), root.kind == .frame,
              root.insertionGeometry == nil else { return nil }
        return root
    }

    static func unavailableReason(in page: DocumentPage?) -> String? {
        guard let root = root(in: page) else {
            return "Page Background needs a website page with one structural Root. Edit individual object fills in Design instead."
        }
        if root.selectionBooleanProperty("locked") { return "Unlock the page Root in Layers before editing its background." }
        if root.selectionBooleanProperty("hidden") { return "Show the page Root in Layers before editing its background." }
        return nil
    }
}

/// Layer mutations remain values compiled by the identity-gated registry.
enum DesignFillLayerEdit: Sendable {
    /// Compatibility operation for the existing single-colour Inspector. It
    /// resolves or creates one solid layer per applicable node so legacy
    /// controls migrate through the v1 write path rather than resurrecting
    /// v4 channel properties.
    case replaceSolid(CanonicalSolidColor?)
    /// Explicit None removes all fill layers and fill-token binding atomically;
    /// an authored empty order prevents legacy/default surface resurrection.
    case clearAll
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
        case .clearAll: result = []
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

/// Noncanonical native text draft. An adopted revision may refresh its command
/// identity without rebuilding the focused field or overwriting unfinished input.
/// Pure navigation destination, resolved from an existing typed binding. It
/// never retargets an override or treats a virtual rendered child as authored.
struct ComponentPropertySourceDestination: Equatable, Sendable {
    let definitionID: PageID
    let sourceNodeID: NodeID
    init?(document: CanonicalDocument, pageID: PageID, instanceID: NodeID,
          property: ComponentOverridePropertyIdentity) {
        guard let page = document.websitePages.first(where: { $0.id == pageID }),
              let instance = page.nodes.first(where: { $0.id == instanceID && $0.kind == .component }),
              let definitionID = CanonicalComponentReference.definitionID(for: instance),
              let definition = document.componentDefinitions.first(where: { $0.id == definitionID }),
              let entry = CanonicalComponentOrganization.entries(in: definition).first(where: { $0.id == property }),
              definition.nodes.contains(where: { $0.id == entry.sourceNodeID }) else { return nil }
        self.definitionID = definitionID; sourceNodeID = entry.sourceNodeID
    }
}

/// Paired definition draft reuses the existing text-draft adoption policy.
/// Binding replacement is a conflict, not permission to re-expose a new ID.
struct ComponentDefinitionTextDraft: Equatable, Sendable {
    var label: ComponentInstanceTextDraft
    var content: ComponentInstanceTextDraft
    private(set) var bindingID: ComponentTextPropertyID?
    private(set) var bindingConflict = false
    var isDirty: Bool { label.isDirty || content.isDirty }
    var hasConflict: Bool { bindingConflict || label.conflict != nil || content.conflict != nil }
    var identity: DesignInspectorOperationIdentity? {
        guard !hasConflict, label.identity == content.identity else { return nil }
        return label.identity
    }
    init(label: String, content: String, bindingID: ComponentTextPropertyID?,
         identity: DesignInspectorOperationIdentity?, selectionIDs: [NodeID]) {
        self.label = .init(committed: label, identity: identity, selectionIDs: selectionIDs)
        self.content = .init(committed: content, identity: identity, selectionIDs: selectionIDs)
        self.bindingID = bindingID
    }
    mutating func adopt(label: String, content: String, bindingID nextBinding: ComponentTextPropertyID?,
                        identity: DesignInspectorOperationIdentity?, selectionIDs: [NodeID]) {
        if isDirty && bindingID != nextBinding { bindingConflict = true }
        if !isDirty && !bindingConflict { bindingID = nextBinding }
        self.label.adopt(committed: label, identity: identity, selectionIDs: selectionIDs)
        self.content.adopt(committed: content, identity: identity, selectionIDs: selectionIDs)
    }
}

struct ComponentInstanceTextDraft: Equatable, Sendable {
    enum Conflict: Equatable, Sendable { case contextChanged, valueChanged }
    var value: String
    private(set) var committed: String
    private(set) var identity: DesignInspectorOperationIdentity?
    private(set) var conflict: Conflict?
    private var context: DesignInspectorOperationIdentity?
    private var selectionIDs: [NodeID]
    var isDirty: Bool { value != committed }

    init(committed: String, identity: DesignInspectorOperationIdentity?, selectionIDs: [NodeID] = []) {
        value = committed; self.committed = committed; self.identity = identity; context = identity
        self.selectionIDs = selectionIDs
    }
    mutating func adopt(committed next: String, identity nextIdentity: DesignInspectorOperationIdentity?, selectionIDs nextSelection: [NodeID] = []) {
        let dirty = isDirty
        if !dirty && conflict == nil {
            self = .init(committed: next, identity: nextIdentity, selectionIDs: nextSelection)
            return
        }
        guard selectionIDs == nextSelection else { identity = nil; conflict = .contextChanged; return }
        if let context, let nextIdentity,
           (context.documentID != nextIdentity.documentID || context.pageID != nextIdentity.pageID || context.sceneID != nextIdentity.sceneID
            ) {
            committed = next; identity = nil; conflict = .contextChanged
            return
        }
        if dirty && next != committed && next != value { conflict = .valueChanged }
        if !dirty { value = next }
        committed = next
        identity = conflict == nil ? nextIdentity : nil
        if let nextIdentity { context = nextIdentity }
    }
    mutating func cancel(committed: String, identity: DesignInspectorOperationIdentity?, selectionIDs: [NodeID] = []) {
        self = .init(committed: committed, identity: identity, selectionIDs: selectionIDs)
    }
}

enum ComponentEdit: Sendable {
    case create(NodeID)
    case createNamed(NodeID, name: String)
    case rename(definitionID: PageID, name: String)
    case insert(definitionID: PageID, parentID: NodeID, geometry: InsertionGeometry)
    case detach(NodeID)
    case delete(definitionID: PageID, detachUses: Bool)
    case exposeText(nodeID: NodeID, label: String, defaultValue: String)
    case removeTextProperty(NodeID)
    case setTextOverride(instanceID: NodeID, propertyID: ComponentTextPropertyID, value: String)
    case resetTextOverride(instanceID: NodeID, propertyID: ComponentTextPropertyID)
    case resetAllTextOverrides(NodeID)
    case exposeVisibility(nodeID: NodeID, label: String, defaultValue: Bool)
    case removeVisibilityProperty(NodeID)
    case setVisibilityOverride(instanceID: NodeID, propertyID: ComponentVisibilityPropertyID, value: Bool)
    case resetVisibilityOverride(instanceID: NodeID, propertyID: ComponentVisibilityPropertyID)
    case resetAllVisibilityOverrides(NodeID)
    case exposeChoice(nodeID: NodeID, label: String)
    case removeChoiceProperty(NodeID)
    case setChoiceOverride(instanceID: NodeID, propertyID: ComponentChoicePropertyID, value: ImageFitMode)
    case resetChoiceOverride(instanceID: NodeID, propertyID: ComponentChoicePropertyID)
    case exposeMedia(nodeID: NodeID, label: String)
    case removeMediaProperty(NodeID)
    case setMediaOverride(instanceID: NodeID, propertyID: ComponentMediaPropertyID, assetID: AssetID)
    case resetMediaOverride(instanceID: NodeID, propertyID: ComponentMediaPropertyID)
    case exposeAction(nodeID: NodeID, label: String)
    case removeActionProperty(NodeID)
    case setActionOverride(instanceID: NodeID, propertyID: ComponentActionPropertyID, target: CanonicalLinkTarget)
    case resetActionOverride(instanceID: NodeID, propertyID: ComponentActionPropertyID)
    case exposeSlot(nodeID: NodeID, label: String)
    case removeSlotProperty(NodeID)
    case organizeProperty(nodeID: NodeID, property: ComponentOverridePropertyIdentity, group: String?, position: Int)
    case resetPropertyOrganization(nodeID: NodeID, property: ComponentOverridePropertyIdentity)
    case resetAllOverrides(NodeID)
    case resetOverrideConflicts(instanceID: NodeID, expectedPropertyIDs: [PropertyID], confirmed: Bool)
}

struct PreparedComponentEdit: Sendable {
    let command: DocumentCommand
    let selectedNodeID: NodeID?
    let definitionID: PageID?
}

/// All UI component actions compile complete graph changes into the existing
/// atomic command kernel. Graph replacement preserves storage order as well as
/// ownership order, and therefore has an exact existing-command inverse.
enum PageStructureEdit: Sendable {
    case convert(NodeID, confirmed: Bool)
    case reorder(NodeID, pointerY: Double)
    case height(NodeID, Double, ResponsiveBreakpoint)
    case padding(NodeID, Double, ResponsiveBreakpoint)
    case alignment(NodeID, ContainerLayoutAlignment)
    case hamburger(NodeID, Bool)
    case editableContents(NodeID)
    case automaticLayout(NodeID)
    case title(NodeID, text: String)
    case showTitle(NodeID, Bool)
    case showContentImage(NodeID, NodeID, Bool)
    case navigationGap(NodeID, Double?, ResponsiveBreakpoint)
    case includePage(NodeID, PageID, Bool)
    case includeAllPages(NodeID)
    case contentLayout(NodeID, axis: ContainerLayoutAxis, gap: Double, alignment: ContainerLayoutAlignment)
    case addLink(owner: NodeID, pageID: PageID)
    case editLink(owner: NodeID, link: NodeID, pageID: PageID, label: String)
    case removeLink(owner: NodeID, link: NodeID)
    case reorderLink(owner: NodeID, link: NodeID, offset: Int)
}

enum PageStructureEditError: Error, LocalizedError {
    case navigationCapacityExceeded
    var errorDescription: String? {
        "This navigation cannot include every page within its supported link limit. Remove unused links or include individual pages; nothing changed."
    }
}

struct PageStructureCommandRegistry {
    func prepare(_ edit: PageStructureEdit, identity: DesignInspectorOperationIdentity,
                 document: CanonicalDocument, context: TransformValidationContext,
                 viewportWidth: Double, breakpoint: ResponsiveBreakpoint, cancelled: Bool = false) throws -> DocumentCommand {
        guard !cancelled else { throw TransformError.cancelled }
        guard context.isLifecycleAvailable else { throw TransformError.lifecycleUnavailable("Page structure editing is unavailable.") }
        guard identity.documentID == document.id else { throw TransformError.staleDocument }
        guard identity.revision == document.revision else { throw TransformError.staleRevision }
        guard document.revision < UInt64.max - 1 else { throw TransformError.revisionExhausted }
        guard identity.sceneID == context.currentSceneID, identity.rendererGeneration == context.rendererGeneration,
              identity.rendererGeneration == document.revision else { throw TransformError.staleRenderer }
        guard identity.pageID == context.activePageID, let pageIndex = document.pages.firstIndex(where: { $0.id == identity.pageID }),
              document.pages[pageIndex].role != .componentDefinition else { throw TransformError.pageUnavailable }
        let page = document.pages[pageIndex]
        let id: NodeID
        switch edit {
        case .convert(let value, _), .reorder(let value, _), .height(let value, _, _), .padding(let value, _, _),
             .alignment(let value, _), .hamburger(let value, _), .title(let value, _),
             .showTitle(let value, _), .showContentImage(let value, _, _), .navigationGap(let value, _, _),
             .includePage(let value, _, _), .includeAllPages(let value), .contentLayout(let value, _, _, _),
             .editableContents(let value), .automaticLayout(let value): id = value
        case .addLink(let value, _), .editLink(let value, _, _, _), .removeLink(let value, _), .reorderLink(let value, _, _): id = value
        }
        guard context.selectedNodeIDs == [id], let owner = page.nodes.first(where: { $0.id == id }) else { throw TransformError.selectionMismatch }
        guard context.availableNodeIDs.contains(id), !owner.selectionBooleanProperty("hidden") else { throw TransformError.unavailableTarget }
        guard !owner.selectionBooleanProperty("locked") else { throw TransformError.lockedTarget }
        var commands: [DocumentCommand] = []
        func set(_ node: DocumentNode, _ key: String, _ value: PropertyValue, origin: PropertyOrigin = .authored) {
            let old = node.insertionProperty(key)
            guard old?.value != value || old?.origin != origin else { return }
            commands.append(.setProperty(.init(pageID: page.id, nodeID: node.id,
                property: .init(id: old?.id ?? PropertyID(), key: .init(rawValue: key), value: value, origin: origin))))
        }
        func requireNavigation() throws {
            guard let role = CanonicalPageFlow.role(owner), role == .header || role == .footer else { throw TransformError.incompatibleGeometry }
        }
        func chromeNode(_ key: String) throws -> DocumentNode {
            try requireNavigation()
            guard let childID = CanonicalPageChrome.reference(key, on: owner),
                  let child = page.nodes.first(where: { $0.id == childID }),
                  !child.selectionBooleanProperty("locked") else { throw TransformError.missingTarget }
            return child
        }
        let navigationContainer = CanonicalPageChrome.reference(CanonicalPageChrome.navigationKey, on: owner)
            .flatMap { reference in page.nodes.first { $0.id == reference } } ?? owner
        func link(_ id: NodeID) throws -> DocumentNode {
            try requireNavigation()
            guard let node = page.nodes.first(where: { $0.id == id }), node.parent == .node(navigationContainer.id), CanonicalPageFlow.isNavigationLink(node),
                  !node.selectionBooleanProperty("locked") else { throw TransformError.missingTarget }
            return node
        }
        switch edit {
        case .convert(_, let confirmed):
            guard confirmed else { throw TransformError.cancelled }
            guard owner.kind == .section, CanonicalPageFlow.role(owner) == nil, owner.insertionGeometry != nil else { throw TransformError.incompatibleGeometry }
            let semantic = CanonicalSemanticElement.resolved(for: owner)?.0
            let role: PageFlowRole = semantic == .header ? .header : semantic == .footer ? .footer : .body
            if role != .body { guard owner.parent == .node(page.rootNodeIDs[0]) else { throw TransformError.incompatibleGeometry } }
            set(owner, CanonicalPageFlow.roleKey, .string(role.rawValue))
            if role != .body {
                commands.append(.moveNode(.init(pageID: page.id, nodeID: id, destination: owner.parent,
                    index: role == .header ? 0 : (page.nodes.first { $0.id == page.rootNodeIDs[0] }?.childIDs.count ?? 0))))
            }
        case .reorder(_, let y):
            guard y.isFinite, CanonicalPageFlow.role(owner) == .body, case .node(let parentID) = owner.parent,
                  let parent = page.nodes.first(where: { $0.id == parentID }) else { throw TransformError.incompatibleGeometry }
            let index = CanonicalPageFlow.insertionIndex(role: .body, parent: parent, page: page, pointerY: y,
                breakpoint: breakpoint, width: viewportWidth, excluding: id)
            let current = parent.childIDs.firstIndex(of: id) ?? -1
            let destination = index - (current < index ? 1 : 0)
            if destination != current { commands.append(.moveNode(.init(pageID: page.id, nodeID: id, destination: owner.parent, index: index))) }
        case .height(_, let value, let scope):
            guard CanonicalPageFlow.role(owner) != nil, scope == breakpoint, value.isFinite,
                  value >= 1, value <= LayoutPolicy.maximumDimension else { throw TransformError.incompatibleGeometry }
            guard scope != .desktop || CanonicalSizingConstraints.effectiveMode(.height, node: owner,
                breakpoint: scope, width: viewportWidth) == .fixed else { throw TransformError.incompatibleGeometry }
            let key = scope == .desktop ? "layout.height" : ResponsiveGeometryResolver.key(.height, breakpoint: scope)
            set(owner, key, .number(value))
        case .padding(_, let value, let scope):
            guard CanonicalPageFlow.role(owner) != nil, scope == breakpoint, value.isFinite, (0...10_000).contains(value),
                  DesignBoxStyleCommandRegistry.resolvedStyle(for: owner)?.padding == nil else { throw TransformError.incompatibleGeometry }
            let key = scope == .desktop ? "layout.padding" : ResponsiveContainerLayoutResolver.key(.padding, breakpoint: scope)
            set(owner, key, .number(value))
        case .navigationGap(_, let value, let scope):
            try requireNavigation()
            guard scope == breakpoint else { throw TransformError.staleRenderer }
            let navigation = try chromeNode(CanonicalPageChrome.navigationKey)
            guard navigation.kind == .stack else { throw TransformError.incompatibleGeometry }
            let key = scope == .desktop ? ContainerLayoutField.gap.propertyKey
                : ResponsiveContainerLayoutResolver.key(.gap, breakpoint: scope)
            if let value {
                guard value.isFinite, (0...10_000).contains(value),
                      scope != .desktop || CanonicalFluidValueCodec.value(for: .gap, node: navigation) == nil
                else { throw TransformError.incompatibleGeometry }
                if navigation.insertionProperty(key)?.value != .number(value) { set(navigation, key, .number(value)) }
            } else if let property = navigation.insertionProperty(key) {
                commands.append(.removeProperty(.init(pageID: page.id, nodeID: navigation.id, propertyID: property.id)))
            }
        case .showContentImage(_, let imageID, let shown):
            try requireNavigation()
            let content = try chromeNode(CanonicalPageChrome.contentKey)
            guard content.childIDs.contains(imageID),
                  let image = page.nodes.first(where: { $0.id == imageID }),
                  image.parent == .node(content.id), image.kind == .image else { throw TransformError.missingTarget }
            guard !image.selectionBooleanProperty("locked") else { throw TransformError.lockedTarget }
            if image.selectionBooleanProperty("hidden") == shown { set(image, "hidden", .boolean(!shown)) }
        case .alignment(_, let alignment): try requireNavigation(); set(owner, CanonicalPageFlow.alignmentKey, .string(alignment.rawValue))
        case .hamburger(_, let enabled): try requireNavigation(); set(owner, CanonicalPageFlow.hamburgerKey, .boolean(enabled))
        case .editableContents:
            try requireNavigation()
            guard CanonicalPageChrome.reference(CanonicalPageChrome.contentKey, on: owner) == nil else { break }
            let contents = CanonicalPageChrome.defaults(ownerID: owner.id, document: document)
            let newNodes = [contents.content, contents.title, contents.navigation]
            guard !page.nodes.contains(where: { candidate in newNodes.contains { $0.id == candidate.id } }),
                  document.pages.reduce(0, { $0 + $1.nodes.count }) + newNodes.count <= InsertionPolicy.maximumNodeCount else {
                throw TransformError.invalidResult
            }
            for (key, value) in contents.references { set(owner, key, value) }
            for original in [contents.content, contents.title, contents.navigation] {
                var inserted = original; inserted.childIDs = []
                commands.append(.insertNode(.init(pageID: page.id, node: inserted,
                    index: original.id == contents.content.id ? owner.childIDs.count : original.id == contents.title.id ? 0 : 1)))
            }
            var contentIndex = 2, linkIndex = 0
            for childID in owner.childIDs {
                guard let child = page.nodes.first(where: { $0.id == childID }), !child.selectionBooleanProperty("locked") else {
                    throw TransformError.lockedTarget
                }
                let isLink = CanonicalPageFlow.isNavigationLink(child)
                commands.append(.moveNode(.init(pageID: page.id, nodeID: child.id,
                    destination: .node(isLink ? contents.navigation.id : contents.content.id), index: isLink ? linkIndex : contentIndex)))
                if isLink { linkIndex += 1 } else { contentIndex += 1 }
            }
        case .automaticLayout:
            let content = try chromeNode(CanonicalPageChrome.contentKey)
            set(content, "layout.axis", .string("horizontal"), origin: .defaulted)
            set(content, "layout.padding", .number(0), origin: .defaulted)
            set(content, "layout.gap", .number(24), origin: .defaulted)
            set(content, "layout.align", .string("center"), origin: .defaulted)
            set(owner, CanonicalPageChrome.arrangementKey, .string("automatic"))
        case .title(_, let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 256,
                  !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw TransformError.incompatibleGeometry }
            set(try chromeNode(CanonicalPageChrome.titleKey), "content.text", .string(text))
        case .showTitle(_, let visible):
            let title = try chromeNode(CanonicalPageChrome.titleKey)
            if title.selectionBooleanProperty("hidden") == visible { set(title, "hidden", .boolean(!visible)) }
        case .includeAllPages:
            try requireNavigation()
            let destinations = document.websitePages.filter { $0.role != .notFound }
            let existing = CanonicalPageChrome.links(owner: owner, page: page)
            let missing = destinations.filter { destination in
                !existing.contains { $0.insertionStringProperty(CanonicalLinkTarget.namespace + "pageID") == destination.id.description }
            }
            guard existing.count + missing.count <= CanonicalPageFlow.maximumLinks else {
                throw PageStructureEditError.navigationCapacityExceeded
            }
            guard document.pages.reduce(0, { $0 + $1.nodes.count }) + missing.count <= InsertionPolicy.maximumNodeCount else {
                throw InsertionError.nodeLimitExceeded
            }
            // Reuse single-page mutations. Reverse equal-index insertions to
            // append in page order without reordering custom existing links.
            func include(_ destination: PageID) throws {
                let command = try prepare(.includePage(id, destination, true), identity: identity,
                    document: document, context: context, viewportWidth: viewportWidth, breakpoint: breakpoint)
                if case .batch(let edits) = command { commands.append(contentsOf: edits) }
                else { commands.append(command) }
            }
            for destination in destinations where existing.contains(where: {
                $0.insertionStringProperty(CanonicalLinkTarget.namespace + "pageID") == destination.id.description
                    && $0.selectionBooleanProperty("hidden")
            }) {
                try include(destination.id)
            }
            for destination in missing.reversed() {
                try include(destination.id)
            }
        case .includePage(_, let pageID, let included):
            try requireNavigation()
            guard document.websitePages.contains(where: { $0.id == pageID && $0.role != .notFound }) else { throw TransformError.missingTarget }
            let matches = CanonicalPageChrome.links(owner: owner, page: page).filter {
                $0.insertionStringProperty(CanonicalLinkTarget.namespace + "pageID") == pageID.description
            }
            if matches.isEmpty, included {
                commands.append(try prepare(.addLink(owner: owner.id, pageID: pageID), identity: identity,
                    document: document, context: context, viewportWidth: viewportWidth, breakpoint: breakpoint))
            } else {
                for node in matches {
                    guard !node.selectionBooleanProperty("locked") else { throw TransformError.lockedTarget }
                    if node.selectionBooleanProperty("hidden") == included { set(node, "hidden", .boolean(!included)) }
                }
            }
        case .contentLayout(_, let axis, let gap, let alignment):
            guard gap.isFinite, (0...10_000).contains(gap) else { throw TransformError.incompatibleGeometry }
            let content = try chromeNode(CanonicalPageChrome.contentKey)
            set(owner, CanonicalPageChrome.arrangementKey, .string("custom"))
            set(content, "layout.axis", .string(axis.rawValue))
            set(content, "layout.gap", .number(gap))
            set(content, "layout.align", .string(alignment.rawValue))
        case .addLink(_, let pageID):
            try requireNavigation()
            guard let destination = document.websitePages.first(where: { $0.id == pageID && $0.role != .notFound }),
                  CanonicalPageChrome.links(owner: owner, page: page).count < CanonicalPageFlow.maximumLinks else { throw TransformError.missingTarget }
            let nodeID = NodeID()
            let node = DocumentNode(id: nodeID, kind: .link, name: "Navigation Link", parent: .node(navigationContainer.id), properties: [
                .init(key: .init(rawValue: CanonicalPageFlow.memberKey), value: .boolean(true), origin: .authored),
                .init(key: .init(rawValue: CanonicalLinkTarget.namespace + "kind"), value: .string("page"), origin: .authored),
                .init(key: .init(rawValue: CanonicalLinkTarget.namespace + "pageID"), value: .string(pageID.description), origin: .authored),
                .init(key: .init(rawValue: CanonicalLinkTarget.labelKey), value: .string(destination.name), origin: .defaulted),
                .init(key: .init(rawValue: "layout.x"), value: .number(0), origin: .defaulted),
                .init(key: .init(rawValue: "layout.y"), value: .number(0), origin: .defaulted),
                .init(key: .init(rawValue: "layout.width"), value: .number(160), origin: .defaulted),
                .init(key: .init(rawValue: "layout.height"), value: .number(32), origin: .defaulted)])
            commands.append(.insertNode(.init(pageID: page.id, node: node, index: navigationContainer.childIDs.count)))
        case .editLink(_, let linkID, let destinationID, let label):
            let node = try link(linkID)
            guard document.websitePages.contains(where: { $0.id == destinationID && $0.role != .notFound }),
                  !label.isEmpty, label.utf8.count <= 256, !label.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw TransformError.missingTarget
            }
            set(node, CanonicalLinkTarget.namespace + "pageID", .string(destinationID.description))
            set(node, CanonicalLinkTarget.labelKey, .string(label))
        case .removeLink(_, let linkID):
            _ = try link(linkID); commands.append(.removeNode(.init(pageID: page.id, nodeID: linkID)))
        case .reorderLink(_, let linkID, let offset):
            _ = try link(linkID)
            let links = navigationContainer.childIDs.filter { child in page.nodes.first { $0.id == child }.map(CanonicalPageFlow.isNavigationLink) == true }
            guard let current = links.firstIndex(of: linkID), [-1, 1].contains(offset), links.indices.contains(current + offset),
                  let target = navigationContainer.childIDs.firstIndex(of: links[current + offset]) else { throw TransformError.incompatibleGeometry }
            commands.append(.moveNode(.init(pageID: page.id, nodeID: linkID, destination: .node(navigationContainer.id), index: offset > 0 ? target + 1 : target)))
        }
        let command = DocumentCommand.batch(commands)
        if commands.isEmpty { return command }
        guard CommandRegistry().availability(for: command, in: document).isEnabled else { throw TransformError.invalidResult }
        return command
    }
}

struct ComponentCommandRegistry {
    /// Shared preflight for native eligibility and the canonical create command.
    /// It allocates no new identities and never changes the selected graph.
    static func creationSourceIDs(_ id: NodeID, page: DocumentPage,
                                  document: CanonicalDocument) throws -> Set<NodeID> {
        guard let root = page.nodes.first(where: { $0.id == id }),
              [.frame, .section, .stack, .grid].contains(root.kind),
              let geometry = root.insertionGeometry,
              [geometry.origin.x, geometry.origin.y, geometry.size.width, geometry.size.height]
                .allSatisfy({ $0.isFinite && abs($0) <= 1_000_000_000 }),
              geometry.size.width >= 1, geometry.size.height >= 1 else {
            throw TransformError.incompatibleGeometry
        }
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        var included = Set<NodeID>(), pending = [id]
        while let next = pending.popLast() {
            guard included.insert(next).inserted, let node = byID[next], node.kind != .component else {
                throw CommandExecutionError.disabled("Nested component authoring is unavailable.")
            }
            guard !CanonicalPageFlow.isManaged(node) else {
                throw CommandExecutionError.disabled("Connected page structure/navigation must remain page-owned; it cannot become component content in this version.")
            }
            pending += node.childIDs
        }
        let descendants = included.subtracting([id])
        for otherPage in document.pages {
            for node in otherPage.nodes where !included.contains(node.id) {
                if CanonicalComponentAction.overrides(on: node).values.contains(where: {
                    if case .section(_, let targetID) = $0 { return descendants.contains(targetID) }
                    return false
                }) {
                    throw CommandExecutionError.disabled("Reset or replace inbound component action destinations before creating this component.")
                }
                if let target = node.insertionStringProperty(CanonicalLinkTarget.namespace + "nodeID"),
                   let targetID = NodeID(uuidString: target), descendants.contains(targetID) {
                    throw CommandExecutionError.disabled("Remove inbound links to child sections before creating this component.")
                }
            }
        }
        return included
    }

    static func draftIdentity(document: CanonicalDocument, pageID: PageID?,
                              renderer: CanvasRenderRequestIdentity?) -> DesignInspectorOperationIdentity? {
        guard let pageID, document.pages.contains(where: { $0.id == pageID }), let renderer,
              renderer.documentID == document.id, renderer.revision == document.revision,
              renderer.sceneGeneration == document.revision else { return nil }
        return .init(documentID: document.id, pageID: pageID, revision: document.revision,
                     sceneID: renderer.sceneID, rendererGeneration: renderer.sceneGeneration)
    }

    func prepare(_ edit: ComponentEdit, identity: DesignInspectorOperationIdentity,
                 in document: CanonicalDocument, context: TransformValidationContext,
                 cancelled: Bool = false) throws -> PreparedComponentEdit {
        guard !cancelled else { throw TransformError.cancelled }
        guard context.isLifecycleAvailable else { throw TransformError.lifecycleUnavailable("Component editing is unavailable.") }
        guard identity.documentID == document.id else { throw TransformError.staleDocument }
        guard identity.revision == document.revision else { throw TransformError.staleRevision }
        guard document.revision < UInt64.max - 1 else { throw TransformError.revisionExhausted }
        guard identity.sceneID == context.currentSceneID,
              identity.rendererGeneration == context.rendererGeneration,
              identity.rendererGeneration == document.revision else { throw TransformError.staleRenderer }
        guard identity.pageID == context.activePageID,
              let index = document.pages.firstIndex(where: { $0.id == identity.pageID }) else { throw TransformError.pageUnavailable }
        var page = document.pages[index]
        switch edit {
        case .exposeText, .removeTextProperty, .exposeVisibility, .removeVisibilityProperty,
             .exposeChoice, .removeChoiceProperty, .exposeMedia, .removeMediaProperty,
             .exposeAction, .removeActionProperty, .exposeSlot, .removeSlotProperty,
             .organizeProperty, .resetPropertyOrganization:
            guard page.role == .componentDefinition else { throw TransformError.incompatibleGeometry }
        default:
            guard page.role != .componentDefinition else {
                throw CommandExecutionError.disabled("Exit definition editing before editing an instance.")
            }
        }
        func replace(_ graph: DocumentPage, at index: Int) -> [DocumentCommand] {
            [.removePage(.init(pageID: graph.id)), .insertPage(.init(page: graph, index: index))]
        }
        func selected(_ id: NodeID, allowHidden: Bool = false) throws -> DocumentNode {
            guard context.selectedNodeIDs == [id] else { throw TransformError.selectionMismatch }
            guard let node = page.nodes.first(where: { $0.id == id }) else { throw TransformError.missingTarget }
            guard context.availableNodeIDs.contains(id) else { throw TransformError.unavailableTarget }
            guard !node.selectionBooleanProperty("locked") else { throw TransformError.lockedTarget }
            guard allowHidden || !node.selectionBooleanProperty("hidden") else { throw TransformError.hiddenTarget }
            return node
        }
        func properties(_ node: DocumentNode, setting: [(String, PropertyValue)] = [], removing: Set<String> = []) throws -> PreparedComponentEdit {
            var removing = removing
            // Removing a binding removes only its organization, not instance intent.
            for (bindingNamespace, kind) in [
                (CanonicalComponentText.namespace, "text"), (CanonicalComponentVisibility.namespace, "visibility"),
                (CanonicalComponentChoice.namespace, "choice"), (CanonicalComponentMedia.namespace, "media"),
                (CanonicalComponentAction.namespace, "action"), (CanonicalComponentSlot.namespace, "slot")]
                where removing.contains(bindingNamespace + "id") {
                removing.insert(CanonicalComponentOrganization.key(kind, "group"))
                removing.insert(CanonicalComponentOrganization.key(kind, "order"))
                removing.insert(CanonicalComponentOrganization.key(kind, "binding"))
            }
            var commands: [DocumentCommand] = []
            var updated = node
            for property in node.properties where removing.contains(property.key.rawValue) {
                commands.append(.removeProperty(.init(pageID: page.id, nodeID: node.id, propertyID: property.id)))
                updated.properties.removeAll { $0.id == property.id }
            }
            for (key, value) in setting {
                let old = node.properties.first { $0.key.rawValue == key }
                guard old?.value != value || old?.origin != .authored else { continue }
                let property = NodeProperty(id: old?.id ?? PropertyID(), key: .init(rawValue: key),
                                            value: value, origin: .authored)
                commands.append(.setProperty(.init(pageID: page.id, nodeID: node.id, property: property)))
                if let i = updated.properties.firstIndex(where: { $0.key == property.key }) { updated.properties[i] = property }
                else { updated.properties.append(property) }
            }
            var candidate = document
            candidate.pages[index].nodes[page.nodes.firstIndex(where: { $0.id == node.id })!] = updated
            try candidate.validate()
            try CanonicalComponentText.validateTransition(from: document, to: candidate)
            try CanonicalComponentVisibility.validateTransition(from: document, to: candidate)
            try CanonicalComponentChoice.validateTransition(from: document, to: candidate)
            try CanonicalComponentMedia.validateTransition(from: document, to: candidate)
            try CanonicalComponentAction.validateTransition(from: document, to: candidate)
            try CanonicalComponentSlot.validateTransition(from: document, to: candidate)
            return .init(command: .batch(commands), selectedNodeID: node.id,
                         definitionID: page.role == .componentDefinition ? page.id : CanonicalComponentReference.definitionID(for: node))
        }
        switch edit {
        case .organizeProperty(let id, let binding, let group, let position):
            _ = try selected(id)
            var entries = CanonicalComponentOrganization.entries(in: page)
            guard let prior = entries.firstIndex(where: { $0.id == binding && $0.sourceNodeID == id }),
                  entries.indices.contains(position), group == nil || CanonicalComponentOrganization.validGroup(group!) else {
                throw CommandExecutionError.disabled("Choose an exposed property, a valid position, and a group of at most 64 bytes without control characters.")
            }
            let entry = entries.remove(at: prior)
            entries.insert(entry, at: position)
            var candidate = document
            var commands: [DocumentCommand] = []
            for (rank, item) in entries.enumerated() {
                guard let nodeIndex = page.nodes.firstIndex(where: { $0.id == item.sourceNodeID }) else { throw TransformError.missingTarget }
                var node = candidate.pages[index].nodes[nodeIndex]
                let fields: [(String, PropertyValue?)] = [
                    (CanonicalComponentOrganization.key(item.id.organizationKind, "binding"), .string(item.id.stableDescription)),
                    (CanonicalComponentOrganization.key(item.id.organizationKind, "order"), .number(Double(rank))),
                    (CanonicalComponentOrganization.key(item.id.organizationKind, "group"),
                     (item.id == binding ? group : item.group).map { .string($0) })]
                for (key, value) in fields {
                    let old = node.properties.first { $0.key.rawValue == key }
                    if let value {
                        guard old?.value != value || old?.origin != .authored else { continue }
                        guard !node.selectionBooleanProperty("locked") else { throw TransformError.lockedTarget }
                        let property = NodeProperty(id: old?.id ?? PropertyID(), key: .init(rawValue: key), value: value, origin: .authored)
                        commands.append(.setProperty(.init(pageID: page.id, nodeID: node.id, property: property)))
                        node.properties.removeAll { $0.key.rawValue == key }; node.properties.append(property)
                    } else if let old {
                        guard !node.selectionBooleanProperty("locked") else { throw TransformError.lockedTarget }
                        commands.append(.removeProperty(.init(pageID: page.id, nodeID: node.id, propertyID: old.id)))
                        node.properties.removeAll { $0.id == old.id }
                    }
                }
                candidate.pages[index].nodes[nodeIndex] = node
            }
            try candidate.validate()
            return .init(command: .batch(commands), selectedNodeID: id, definitionID: page.id)
        case .resetPropertyOrganization(let id, let binding):
            let node = try selected(id)
            guard CanonicalComponentOrganization.bindings(on: node).contains(where: { $0.0 == binding }) else {
                throw TransformError.missingTarget
            }
            return try properties(node, removing: [CanonicalComponentOrganization.key(binding.organizationKind, "group"),
                                                   CanonicalComponentOrganization.key(binding.organizationKind, "binding"),
                                                   CanonicalComponentOrganization.key(binding.organizationKind, "order")])
        case .rename(let definitionID, let draft):
            guard let definition = document.componentDefinitions.first(where: { $0.id == definitionID }) else {
                throw TransformError.missingTarget
            }
            let name: String
            do { name = try StaticPagePolicy.name(draft) }
            catch {
                throw CommandExecutionError.disabled(
                    "Enter a component name of 1–256 UTF-8 bytes without control characters."
                )
            }
            guard name != definition.name else {
                throw CommandExecutionError.disabled("The component already has that name.")
            }
            guard !document.componentDefinitions.contains(where: {
                $0.id != definitionID && $0.name.caseInsensitiveCompare(name) == .orderedSame
            }) else {
                throw CommandExecutionError.disabled("Use a unique component name.")
            }
            var commands: [DocumentCommand] = []
            for (pageIndex, original) in document.pages.enumerated() where original.role != .componentDefinition {
                var graph = original
                var changed = false
                for nodeIndex in graph.nodes.indices where
                    CanonicalComponentReference.definitionID(for: graph.nodes[nodeIndex]) == definitionID
                {
                    if graph.nodes[nodeIndex].name != name {
                        graph.nodes[nodeIndex].name = name
                        changed = true
                    }
                }
                if changed { commands += replace(graph, at: pageIndex) }
            }
            commands.append(.renamePage(.init(pageID: definitionID, name: name)))
            return .init(command: .batch(commands), selectedNodeID: context.selectedNodeIDs.first,
                         definitionID: definitionID)
        case .exposeText(let id, let label, let text):
            let node = try selected(id)
            guard node.kind == .text, CanonicalComponentText.validLabel(label),
                  text.utf8.count <= CanonicalComponentText.maximumTextBytes else {
                throw CommandExecutionError.disabled("Use a unique, nonempty property name and plain text of at most 64 KiB.")
            }
            let propertyID = CanonicalComponentText.property(on: node)?.id ?? ComponentTextPropertyID()
            return try properties(node, setting: [
                (CanonicalComponentText.namespace + "id", .string(propertyID.description)),
                (CanonicalComponentText.namespace + "label", .string(label)),
                (CanonicalComponentText.namespace + "type", .string("plain-text")), ("content.text", .string(text))])
        case .removeTextProperty(let id):
            let node = try selected(id)
            guard node.kind == .text else { throw TransformError.incompatibleGeometry }
            return try properties(node, removing: CanonicalComponentText.metadataKeys)
        case .setTextOverride(let id, let propertyID, let text):
            let node = try selected(id)
            guard let definitionID = CanonicalComponentReference.definitionID(for: node),
                  let definition = document.componentDefinitions.first(where: { $0.id == definitionID }),
                  CanonicalComponentText.properties(in: definition).contains(where: { $0.id == propertyID }),
                  text.utf8.count <= CanonicalComponentText.maximumTextBytes else {
                throw CommandExecutionError.disabled("The text binding is missing or the draft exceeds 64 KiB. Restore the binding or shorten the draft.")
            }
            return try properties(node, setting: [(CanonicalComponentText.overrideKey(propertyID), .string(text))])
        case .resetTextOverride(let id, let propertyID):
            let node = try selected(id)
            guard node.kind == .component else { throw TransformError.incompatibleGeometry }
            return try properties(node, removing: [CanonicalComponentText.overrideKey(propertyID)])
        case .resetAllTextOverrides(let id):
            let node = try selected(id)
            guard node.kind == .component else { throw TransformError.incompatibleGeometry }
            return try properties(node, removing: Set(node.properties.map(\.key.rawValue).filter {
                $0.hasPrefix(CanonicalComponentText.overrideNamespace)
            }))
        case .exposeVisibility(let id, let label, let value):
            let node = try selected(id, allowHidden: true)
            guard CanonicalComponentVisibility.eligibleKinds.contains(node.kind),
                  !page.rootNodeIDs.contains(id), CanonicalComponentVisibility.validLabel(label) else {
                throw CommandExecutionError.disabled("Select an eligible definition child and use a unique, nonempty property name.")
            }
            let propertyID = CanonicalComponentVisibility.property(on: node)?.id ?? ComponentVisibilityPropertyID()
            return try properties(node, setting: [
                (CanonicalComponentVisibility.namespace + "id", .string(propertyID.description)),
                (CanonicalComponentVisibility.namespace + "label", .string(label)),
                (CanonicalComponentVisibility.namespace + "type", .string("boolean-visibility")),
                (CanonicalComponentVisibility.namespace + "default", .boolean(value))])
        case .removeVisibilityProperty(let id):
            let node = try selected(id, allowHidden: true)
            guard CanonicalComponentVisibility.property(on: node) != nil else { throw TransformError.incompatibleGeometry }
            return try properties(node, removing: CanonicalComponentVisibility.metadataKeys)
        case .setVisibilityOverride(let id, let propertyID, let value):
            let node = try selected(id)
            guard let definitionID = CanonicalComponentReference.definitionID(for: node),
                  let definition = document.componentDefinitions.first(where: { $0.id == definitionID }),
                  CanonicalComponentVisibility.properties(in: definition).contains(where: { $0.id == propertyID }) else {
                throw CommandExecutionError.disabled("The visibility binding is missing. Restore it before editing this instance.")
            }
            return try properties(node, setting: [(CanonicalComponentVisibility.overrideKey(propertyID), .boolean(value))])
        case .resetVisibilityOverride(let id, let propertyID):
            let node = try selected(id)
            guard node.kind == .component else { throw TransformError.incompatibleGeometry }
            return try properties(node, removing: [CanonicalComponentVisibility.overrideKey(propertyID)])
        case .resetAllVisibilityOverrides(let id):
            let node = try selected(id)
            guard node.kind == .component else { throw TransformError.incompatibleGeometry }
            return try properties(node, removing: Set(node.properties.map(\.key.rawValue).filter {
                $0.hasPrefix(CanonicalComponentVisibility.overrideNamespace)
            }))
        case .exposeChoice(let id, let label):
            let node = try selected(id)
            guard node.kind == .image, CanonicalComponentText.validLabel(label),
                  CanonicalImageStyle.resolve(node) != nil else {
                throw CommandExecutionError.disabled("Select an Image in the component definition and use a nonempty property name.")
            }
            let propertyID = CanonicalComponentChoice.property(on: node)?.id ?? ComponentChoicePropertyID()
            return try properties(node, setting: [
                (CanonicalComponentChoice.namespace + "id", .string(propertyID.description)),
                (CanonicalComponentChoice.namespace + "label", .string(label)),
                (CanonicalComponentChoice.namespace + "type", .string("image-fit"))])
        case .removeChoiceProperty(let id):
            let node = try selected(id)
            guard CanonicalComponentChoice.property(on: node) != nil else { throw TransformError.incompatibleGeometry }
            return try properties(node, removing: CanonicalComponentChoice.metadataKeys)
        case .setChoiceOverride(let id, let propertyID, let value):
            let node = try selected(id)
            guard let definitionID = CanonicalComponentReference.definitionID(for: node),
                  let definition = document.componentDefinitions.first(where: { $0.id == definitionID }),
                  CanonicalComponentChoice.properties(in: definition).contains(where: { $0.id == propertyID }) else {
                throw CommandExecutionError.disabled("The choice binding is missing. Restore it before editing this instance.")
            }
            return try properties(node, setting: [(CanonicalComponentChoice.overrideKey(propertyID), .string(value.rawValue))])
        case .resetChoiceOverride(let id, let propertyID):
            let node = try selected(id)
            guard node.kind == .component else { throw TransformError.incompatibleGeometry }
            return try properties(node, removing: [CanonicalComponentChoice.overrideKey(propertyID)])
        case .exposeMedia(let id, let label):
            let node = try selected(id)
            guard node.kind == .image, CanonicalComponentText.validLabel(label),
                  CanonicalImageStyle.resolve(node) != nil else {
                throw CommandExecutionError.disabled("Select an Image in the component definition and use a nonempty property name.")
            }
            let propertyID = CanonicalComponentMedia.property(on: node)?.id ?? ComponentMediaPropertyID()
            return try properties(node, setting: [
                (CanonicalComponentMedia.namespace + "id", .string(propertyID.description)),
                (CanonicalComponentMedia.namespace + "label", .string(label)),
                (CanonicalComponentMedia.namespace + "type", .string("image-asset"))])
        case .removeMediaProperty(let id):
            let node = try selected(id)
            guard CanonicalComponentMedia.property(on: node) != nil else { throw TransformError.incompatibleGeometry }
            return try properties(node, removing: CanonicalComponentMedia.metadataKeys)
        case .setMediaOverride(let id, let propertyID, let assetID):
            let node = try selected(id)
            guard document.imageAssets.contains(where: { $0.id == assetID }),
                  let definitionID = CanonicalComponentReference.definitionID(for: node),
                  let definition = document.componentDefinitions.first(where: { $0.id == definitionID }),
                  CanonicalComponentMedia.properties(in: definition).contains(where: { $0.id == propertyID }) else {
                throw CommandExecutionError.disabled("The media binding or selected image asset is unavailable.")
            }
            return try properties(node, setting: [(CanonicalComponentMedia.overrideKey(propertyID), .string(assetID.description))])
        case .resetMediaOverride(let id, let propertyID):
            let node = try selected(id)
            guard node.kind == .component else { throw TransformError.incompatibleGeometry }
            return try properties(node, removing: [CanonicalComponentMedia.overrideKey(propertyID)])
        case .exposeAction(let id, let label):
            let node = try selected(id)
            guard node.kind.isLinkControl, CanonicalComponentText.validLabel(label),
                  (try? CanonicalLinkTarget.resolve(node)) != nil else {
                throw CommandExecutionError.disabled("Select a Button or Link in the component definition and use a nonempty property name.")
            }
            let propertyID = CanonicalComponentAction.property(on: node)?.id ?? ComponentActionPropertyID()
            return try properties(node, setting: [
                (CanonicalComponentAction.namespace + "id", .string(propertyID.description)),
                (CanonicalComponentAction.namespace + "label", .string(label)),
                (CanonicalComponentAction.namespace + "type", .string("link-target"))])
        case .removeActionProperty(let id):
            let node = try selected(id)
            guard CanonicalComponentAction.property(on: node) != nil else { throw TransformError.incompatibleGeometry }
            return try properties(node, removing: CanonicalComponentAction.metadataKeys)
        case .setActionOverride(let id, let propertyID, let target):
            let node = try selected(id)
            if case .external(let url) = target, !CanonicalLinkTarget.validateExternal(url) {
                throw CommandExecutionError.disabled("Use a valid HTTP(S) destination without credentials or whitespace.")
            }
            guard CanonicalComponentAction.decode(CanonicalComponentAction.encode(target)) == target,
                  !target.isMissing(in: document),
                  let definitionID = CanonicalComponentReference.definitionID(for: node),
                  let definition = document.componentDefinitions.first(where: { $0.id == definitionID }),
                  CanonicalComponentAction.properties(in: definition).contains(where: { $0.id == propertyID }) else {
                throw CommandExecutionError.disabled("The action binding or selected destination is unavailable.")
            }
            return try properties(node, setting: [(CanonicalComponentAction.overrideKey(propertyID), .string(CanonicalComponentAction.encode(target)))])
        case .resetActionOverride(let id, let propertyID):
            let node = try selected(id)
            guard node.kind == .component else { throw TransformError.incompatibleGeometry }
            return try properties(node, removing: [CanonicalComponentAction.overrideKey(propertyID)])
        case .exposeSlot(let id, let label):
            let node = try selected(id)
            guard CanonicalComponentSlot.supportedKinds.contains(node.kind), !page.rootNodeIDs.contains(id),
                  CanonicalComponentText.validLabel(label) else {
                throw CommandExecutionError.disabled("Select a non-root Frame, Section, Stack or Grid in the definition and use a unique nonempty slot name.")
            }
            let propertyID = CanonicalComponentSlot.property(on: node)?.id ?? ComponentSlotPropertyID()
            return try properties(node, setting: [
                (CanonicalComponentSlot.namespace + "id", .string(propertyID.description)),
                (CanonicalComponentSlot.namespace + "label", .string(label)),
                (CanonicalComponentSlot.namespace + "type", .string("ordered-fallback-children"))])
        case .removeSlotProperty(let id):
            let node = try selected(id)
            guard CanonicalComponentSlot.property(on: node) != nil else { throw TransformError.incompatibleGeometry }
            return try properties(node, removing: CanonicalComponentSlot.metadataKeys)
        case .resetOverrideConflicts(let id, let expected, let confirmed):
            let node = try selected(id)
            guard confirmed else { throw TransformError.cancelled }
            guard node.kind == .component, !expected.isEmpty, Set(expected).count == expected.count else {
                throw TransformError.incompatibleGeometry
            }
            let conflicts = try CanonicalComponentOverrides.conflicts(instance: node, document: document)
            let liveIDs = Set(conflicts.map(\.authoredPropertyID))
            guard Set(expected).isSubset(of: liveIDs) else {
                throw CommandExecutionError.disabled("The retained conflicts changed. Review the current values before resetting.")
            }
            let keys = Set(node.properties.filter { expected.contains($0.id) }.map(\.key.rawValue))
            guard keys.count == expected.count else { throw TransformError.missingTarget }
            return try properties(node, removing: keys)
        case .resetAllOverrides(let id):
            let node = try selected(id)
            guard node.kind == .component else { throw TransformError.incompatibleGeometry }
            return try properties(node, removing: Set(node.properties.map(\.key.rawValue).filter {
                $0.hasPrefix(CanonicalComponentText.overrideNamespace)
                    || $0.hasPrefix(CanonicalComponentVisibility.overrideNamespace)
                    || $0.hasPrefix(CanonicalComponentChoice.overrideNamespace)
                    || $0.hasPrefix(CanonicalComponentMedia.overrideNamespace)
                    || $0.hasPrefix(CanonicalComponentAction.overrideNamespace)
            }))
        case .create(let id), .createNamed(let id, _):
            let root = try selected(id)
            let included = try Self.creationSourceIDs(id, page: page, document: document)
            let componentName: String
            if case .createNamed(_, let draft) = edit {
                do { componentName = try StaticPagePolicy.name(draft) }
                catch { throw CommandExecutionError.disabled("Enter a component name of 1–256 UTF-8 bytes without control characters.") }
                guard !document.componentDefinitions.contains(where: {
                    $0.name.caseInsensitiveCompare(componentName) == .orderedSame
                }) else { throw CommandExecutionError.disabled("A component already uses this name.") }
            } else {
                componentName = root.name
            }
            let definitionID = PageID()
            let ids = Dictionary(uniqueKeysWithValues: included.map { ($0, NodeID()) })
            let nodes = page.nodes.filter { included.contains($0.id) }.map { node in
                var properties = node.properties.map { NodeProperty(key: $0.key, value: $0.value, origin: $0.origin) }
                for i in properties.indices {
                    if properties[i].key.rawValue == CanonicalLinkTarget.namespace + "nodeID",
                       case .string(let value) = properties[i].value,
                       let oldID = NodeID(uuidString: value), let newID = ids[oldID] {
                        properties[i].value = .string(newID.description)
                        if let pageIndex = properties.firstIndex(where: { $0.key.rawValue == CanonicalLinkTarget.namespace + "pageID" }) {
                            properties[pageIndex].value = .string(definitionID.description)
                        }
                    }
                }
                let parent: NodeParent = node.id == id ? .page(definitionID) : {
                    if case .node(let parentID) = node.parent { return .node(ids[parentID]!) }
                    return .page(definitionID)
                }()
                return DocumentNode(id: ids[node.id]!, kind: node.kind, name: node.name, parent: parent,
                    childIDs: node.childIDs.map { ids[$0]! }, properties: properties)
            }
            let definition = DocumentPage(id: definitionID, name: componentName,
                route: .init(rawValue: ""), role: .componentDefinition, provenance: .authored,
                rootNodeIDs: [ids[id]!], nodes: nodes)
            let instance = Self.instance(id: id, name: componentName, parent: root.parent,
                                         definitionID: definitionID, geometry: root.insertionGeometry!,
                                         preserved: root.properties)
            page.nodes = page.nodes.compactMap { node in
                node.id == id ? instance : included.contains(node.id) ? nil : node
            }
            return .init(command: .batch(replace(page, at: index) + [.insertPage(.init(page: definition, index: document.pages.count))]),
                         selectedNodeID: id, definitionID: definitionID)
        case .insert(let definitionID, let parentID, let geometry):
            guard let definition = document.componentDefinitions.first(where: { $0.id == definitionID }),
                  let parentIndex = page.nodes.firstIndex(where: { $0.id == parentID }),
                  page.nodes[parentIndex].kind.acceptsAuthoredChildren,
                  !page.nodes[parentIndex].selectionBooleanProperty("locked"),
                  !page.nodes[parentIndex].selectionBooleanProperty("hidden"),
                  [geometry.origin.x, geometry.origin.y, geometry.size.width, geometry.size.height].allSatisfy(\.isFinite),
                  geometry.size.width > 0, geometry.size.height > 0 else { throw TransformError.incompatibleGeometry }
            let instance = Self.instance(id: NodeID(), name: definition.name, parent: .node(parentID),
                                         definitionID: definitionID, geometry: geometry)
            page.nodes[parentIndex].childIDs.append(instance.id)
            page.nodes.append(instance)
            return .init(command: .batch(replace(page, at: index)), selectedNodeID: instance.id, definitionID: definitionID)
        case .detach(let id):
            let instance = try selected(id)
            guard let definitionID = CanonicalComponentReference.definitionID(for: instance),
                  let definition = document.componentDefinitions.first(where: { $0.id == definitionID }),
                  let expanded = ComponentGraphResolver.detachedNodes(instance, definition: definition, page: page) else {
                throw CommandExecutionError.disabled("The definition or an authored text binding is missing. Restore it or reset unresolved values before detaching.")
            }
            page.nodes = page.nodes.flatMap { $0.id == id ? expanded : [$0] }
            return .init(command: .batch(replace(page, at: index)), selectedNodeID: id, definitionID: nil)
        case .delete(let definitionID, let detachUses):
            guard let definition = document.componentDefinitions.first(where: { $0.id == definitionID }) else { throw TransformError.missingTarget }
            var commands: [DocumentCommand] = []
            for (pageIndex, original) in document.pages.enumerated() where original.role != .componentDefinition {
                var graph = original
                let uses = graph.nodes.filter { CanonicalComponentReference.definitionID(for: $0) == definitionID }
                guard uses.isEmpty || detachUses else {
                    throw CommandExecutionError.disabled("This component is in use. Choose Detach Uses and Delete, or cancel.")
                }
                for instance in uses {
                    guard !instance.selectionBooleanProperty("locked") else { throw TransformError.lockedTarget }
                    guard let expanded = ComponentGraphResolver.detachedNodes(instance, definition: definition,
                        page: graph) else { throw TransformError.incompatibleGeometry }
                    graph.nodes = graph.nodes.flatMap { $0.id == instance.id ? expanded : [$0] }
                }
                if !uses.isEmpty { commands += replace(graph, at: pageIndex) }
            }
            commands += document.guides.filter { $0.pageID == definitionID }.map { .removeGuide(.init(guideID: $0.id)) }
            commands.append(.removePage(.init(pageID: definitionID)))
            return .init(command: .batch(commands), selectedNodeID: nil, definitionID: nil)
        }
    }

    private static func instance(id: NodeID, name: String, parent: NodeParent, definitionID: PageID,
                                 geometry: InsertionGeometry, preserved: [NodeProperty] = []) -> DocumentNode {
        var properties = preserved.filter {
            $0.key.rawValue.hasPrefix("responsive.geometry.v1.") || $0.key.rawValue.hasPrefix("responsive.visibility.v1.")
                || ["hidden", "locked"].contains($0.key.rawValue)
        }
        for (key, value) in [("layout.x", geometry.origin.x), ("layout.y", geometry.origin.y),
                             ("layout.width", geometry.size.width), ("layout.height", geometry.size.height)] {
            properties.append(preserved.first(where: { $0.key.rawValue == key })
                ?? NodeProperty(key: .init(rawValue: key), value: .number(value)))
        }
        properties.append(NodeProperty(key: .init(rawValue: CanonicalComponentReference.key), value: .string(definitionID.description)))
        return DocumentNode(id: id, kind: .component, name: name, parent: parent, properties: properties)
    }
}

struct DesignInspectorOperationIdentity: Equatable, Sendable {
    let documentID: DocumentID
    let pageID: PageID
    let revision: UInt64
    let sceneID: CanvasViewportSceneID
    let rendererGeneration: UInt64
}

/// Project metadata uses the same immutable scene/revision boundary as Inspector
/// commands, but does not require a canvas object selection.
struct WebsiteMetadataCommandRegistry {
    static let requirementIDs: Set<String> = ["SF-1207-001", "SF-1207-002", "SF-1207-003", "SF-1207-004", "SF-1207-005", "SF-1207-006", "SF-1207-008"]

    func prepare(_ metadata: WebsiteMetadata?, identity: DesignInspectorOperationIdentity,
                 document: CanonicalDocument, context: TransformValidationContext,
                 cancelled: Bool = false) throws -> DocumentCommand {
        guard !cancelled else { throw TransformError.cancelled }
        guard context.isLifecycleAvailable else {
            throw TransformError.lifecycleUnavailable("Site Settings are unavailable while the document is busy.")
        }
        guard identity.documentID == document.id else { throw TransformError.staleDocument }
        guard identity.revision == document.revision else { throw TransformError.staleRevision }
        guard document.revision < UInt64.max - 1 else { throw TransformError.revisionExhausted }
        guard identity.sceneID == context.currentSceneID,
              identity.rendererGeneration == context.rendererGeneration,
              identity.rendererGeneration == document.revision else { throw TransformError.staleRenderer }
        guard identity.pageID == context.activePageID,
              document.pages.contains(where: { $0.id == identity.pageID && $0.role != .componentDefinition })
        else { throw TransformError.pageUnavailable }
        let normalized = metadata?.isEmpty == true ? nil : metadata
        var candidate = document
        candidate.websiteMetadata = normalized
        try candidate.validate()
        guard normalized != document.websiteMetadata else { throw DesignInspectorError.noChanges }
        return .setWebsiteMetadata(.init(documentID: document.id, metadata: normalized))
    }
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
    static let fillKinds: Set<NodeKind> = [.frame, .section, .stack, .grid, .button]

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
        guard fillKinds.contains(node.kind) || node.kind.isTextual else { return nil }
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

    static func opacityValue(nodes: [DocumentNode], reusableStyles: CanonicalReusableStyleIndex? = nil) -> DesignInspectorOpacityValue {
        let values = nodes.compactMap { node -> (Double, PropertyOrigin)? in
            guard let local = resolvedOpacity(for: node) else { return nil }
            guard let reusableStyles,
                  let resolved = try? CanonicalResolvedAppearance.resolve(node: node, index: reusableStyles) else { return local }
            let inherits = node.insertionProperty("style.opacity") == nil
                && CanonicalReusableStyleIndex.appliedIDs(node).contains { reusableStyles.byID[$0]?.opacity != nil }
            return (resolved.opacity, inherits ? .authored : local.1)
        }
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
        let inheritedStyles = try CanonicalReusableStyleIndex(document: document)
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
            if old == nil {
                if CanonicalReusableStyleIndex.appliedIDs(node).contains(where: { inheritedStyles.byID[$0]?.opacity != nil }),
                   try CanonicalResolvedAppearance.resolve(node: node, index: inheritedStyles).opacity == opacity {
                    continue // Native unchanged reconciliation must not bake inherited opacity.
                }
            }
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
        let clearingAppearanceIndex: CanonicalReusableStyleIndex?
        if case .clearAll = command.edit {
            clearingAppearanceIndex = try CanonicalReusableStyleIndex(document: document)
        } else { clearingAppearanceIndex = nil }

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
            let clearsAll: Bool = if case .clearAll = command.edit { true } else { false }
            guard clearsAll || LocalColorTokenBinding.id(for: node) == nil else {
                skipped.append(id)
                skippedReasons[id] = "Unbind the color token before editing literal fill layers."
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
            let hasInheritedFill = try clearingAppearanceIndex.map {
                try CanonicalResolvedAppearance.resolve(node: node, index: $0).fill != nil
            } ?? false
            if clearsAll, before.isEmpty, LocalColorTokenBinding.id(for: node) == nil,
               node.insertionProperty(CanonicalFillLayerCodec.orderKey) == nil,
               !hasInheritedFill,
               !node.properties.contains(where: { legacyKeys.contains($0.key.rawValue) }) {
                continue // An already omitted transparent background is neutral.
            }
            guard after != before || CanonicalFillLayerCodec.layers(for: node) == nil
                    || (clearsAll && LocalColorTokenBinding.id(for: node) != nil) else { continue }

            let desired = CanonicalFillLayerCodec.propertyValues(for: after)
            let owned = node.properties.filter {
                $0.key.rawValue.hasPrefix("style.fill.layers.v1.") || legacyKeys.contains($0.key.rawValue)
                    || (clearsAll && ($0.key.rawValue == LocalColorTokenBinding.key(for: .fill)
                        || $0.key.rawValue == LocalColorTokenBinding.legacyKey))
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

// MARK: - SF-0504 / SF-0510 / SF-0511 positioning and reusable/state styles

enum PositionInsetEdge: String, CaseIterable, Sendable { case top, right, bottom, left }

enum ReusableAppearanceProperty: String, Sendable { case fill, opacity }

struct ReusableStyleSelectionCapture: Equatable, Sendable {
    let fill: CanonicalSolidColor
    let opacity: Double
    let applicableCount: Int
    let skippedCount: Int
    let boundFillCount: Int
}

enum AdvancedStyleEdit: Sendable {
    case positionMode(CanonicalPositionMode)
    case positionInset(PositionInsetEdge, Double?)
    case zIndex(Int)
    case createReusableStyle(id: ReusableStyleID, name: String, fill: CanonicalSolidColor?, opacity: Double?)
    case updateReusableStyle(id: ReusableStyleID, name: String, fill: CanonicalSolidColor?, opacity: Double?)
    case removeReusableStyle(ReusableStyleID)
    case applyReusableStyles([ReusableStyleID])
    case linkReusableStyle(ReusableStyleID)
    case unlinkReusableStyle(ReusableStyleID)
    case moveReusableStyle(ReusableStyleID, offset: Int)
    case useLinkedAppearance(ReusableAppearanceProperty)
    case setState(state: CanonicalInteractionStyleState, id: UUID, fill: CanonicalSolidColor?, opacity: Double?)
    case removeState(CanonicalInteractionStyleState)
}

struct AdvancedStyleCommand: Sendable {
    let identity: DesignInspectorOperationIdentity
    let orderedNodeIDs: [NodeID]
    let edit: AdvancedStyleEdit
    let provenance: DesignInspectorProvenance
    let cancelled: Bool
}

enum AdvancedStyleCommandError: Error, LocalizedError, Equatable, Sendable {
    case stale, cancelled, invalidValue, noSelection, duplicateTarget, unavailable(String), noChanges
    var errorDescription: String? { switch self {
    case .stale: "The document, selection, or canvas changed before the style edit could commit."
    case .cancelled: "The style draft was cancelled; committed content is unchanged."
    case .invalidValue: "Enter a complete finite value supported by the selected style property."
    case .noSelection: "Select an applicable object before editing positioning or styles."
    case .duplicateTarget: "The same object cannot appear twice in one style edit."
    case .unavailable(let reason): reason
    case .noChanges: "The selected objects already have that positioning or style value."
    } }
}

struct AdvancedStyleCommandRegistry: Sendable {
    static let requirementIDs = Set(
        (1...8).map { String(format: "SF-0504-%03d", $0) }
        + (1...8).map { String(format: "SF-0510-%03d", $0) }
        + (1...8).map { String(format: "SF-0511-%03d", $0) }
    )
    static let appearanceKinds: Set<NodeKind> = [.frame, .section, .stack, .grid, .button]

    static func captureSelection(_ nodes: [DocumentNode], in document: CanonicalDocument) throws -> ReusableStyleSelectionCapture {
        let applicable = nodes.filter { appearanceKinds.contains($0.kind) }
        guard !applicable.isEmpty else { throw AdvancedStyleCommandError.noSelection }
        let index = try CanonicalReusableStyleIndex(document: document)
        var samples: [(CanonicalSolidColor, Double)] = []
        for node in applicable {
            guard CanonicalImageFill.resolve(node) == nil else {
                throw AdvancedStyleCommandError.unavailable("Reusable snapshots support one solid fill and opacity; image fills remain local.")
            }
            let appearance = try CanonicalResolvedAppearance.resolve(node: node, index: index)
            let layers = LocalColorTokenResolver.resolvedLayers(for: node, in: document).filter(\.isEnabled)
            let fill: CanonicalSolidColor?
            if layers.count == 1, layers[0].kind == .solid { fill = layers[0].solidColor }
            else if layers.isEmpty, CanonicalFillLayerCodec.layers(for: node) == nil { fill = appearance.fill }
            else { fill = nil }
            guard let fill else {
                throw AdvancedStyleCommandError.unavailable("Capture needs one common solid fill and opacity. Gradients, layered fills and Transparent / None remain local; they are not flattened or replaced.")
            }
            samples.append((fill, appearance.opacity))
        }
        guard let first = samples.first, samples.allSatisfy({ $0.0 == first.0 && $0.1 == first.1 }) else {
            throw AdvancedStyleCommandError.unavailable("The applicable selection has mixed fill or opacity. Choose matching values before capturing a reusable snapshot.")
        }
        guard let storedColor = CanonicalSolidColor.parse(hexadecimal: first.0.hexadecimalRGBA) else {
            throw AdvancedStyleCommandError.invalidValue
        }
        return .init(fill: storedColor, opacity: first.1, applicableCount: applicable.count,
            skippedCount: nodes.count - applicable.count,
            boundFillCount: applicable.filter { LocalColorTokenBinding.id(for: $0) != nil }.count)
    }

    func prepare(
        _ command: AdvancedStyleCommand,
        in document: CanonicalDocument,
        context: TransformValidationContext
    ) throws -> PreparedDesignInspectorEdit {
        guard !command.cancelled else { throw AdvancedStyleCommandError.cancelled }
        guard context.isLifecycleAvailable else {
            throw AdvancedStyleCommandError.unavailable(
                context.lifecycleDisabledReason ?? "Style editing is unavailable during the current document operation."
            )
        }
        guard command.identity.documentID == document.id,
              command.identity.revision == document.revision,
              command.identity.pageID == context.activePageID,
              command.identity.sceneID == context.currentSceneID,
              command.identity.rendererGeneration == context.rendererGeneration,
              command.orderedNodeIDs == context.selectedNodeIDs else {
            throw AdvancedStyleCommandError.stale
        }
        guard document.revision < UInt64.max else {
            throw AdvancedStyleCommandError.unavailable("The document revision cannot accept another style edit.")
        }
        guard !command.orderedNodeIDs.isEmpty else { throw AdvancedStyleCommandError.noSelection }
        guard Set(command.orderedNodeIDs).count == command.orderedNodeIDs.count else {
            throw AdvancedStyleCommandError.duplicateTarget
        }
        guard let page = document.pages.first(where: { $0.id == command.identity.pageID }) else {
            throw AdvancedStyleCommandError.unavailable("The active page is unavailable.")
        }
        let index = try CanonicalReusableStyleIndex(document: document)

        switch command.edit {
        case .createReusableStyle(let id, let name, let fill, let opacity):
            guard index.byID[id] == nil else { throw AdvancedStyleCommandError.invalidValue }
            return try definitionEdit(id: id, name: name, fill: fill, opacity: opacity,
                page: page, ownerNode: nil, existing: nil)
        case .updateReusableStyle(let id, let name, let fill, let opacity):
            guard let existing = index.byID[id] else {
                throw AdvancedStyleCommandError.unavailable("The reusable style no longer exists.")
            }
            guard let owner = definitionOwner(id: id, in: document),
                  let ownerPage = document.pages.first(where: { $0.id == owner.pageID }) else {
                throw AdvancedStyleCommandError.unavailable("The reusable style owner is unavailable.")
            }
            return try definitionEdit(id: id, name: name, fill: fill, opacity: opacity,
                page: ownerPage, ownerNode: owner.node, existing: existing)
        case .removeReusableStyle(let id):
            guard index.byID[id] != nil else {
                throw AdvancedStyleCommandError.unavailable("The reusable style no longer exists.")
            }
            guard !document.pages.flatMap(\.nodes).contains(where: {
                (try? CanonicalReusableStyleIndex.strictlyDecodedAppliedIDs($0).contains(id)) == true
            }) else {
                throw AdvancedStyleCommandError.unavailable("Detach this reusable style from its objects before deleting it.")
            }
            guard let owner = definitionOwner(id: id, in: document) else {
                throw AdvancedStyleCommandError.unavailable("The reusable style owner is unavailable.")
            }
            let prefix = CanonicalReusableStyleIndex.namespace + "definition.\(id.description)."
            let commands = owner.node.properties.filter { $0.key.rawValue.hasPrefix(prefix) }.map {
                DocumentCommand.removeProperty(.init(pageID: owner.pageID, nodeID: owner.node.id, propertyID: $0.id))
            }
            guard !commands.isEmpty else { throw AdvancedStyleCommandError.noChanges }
            return .init(applicableNodeIDs: [owner.node.id], skippedNodeIDs: [], skippedReasons: [:],
                         documentCommand: .batch(commands))
        default:
            return try selectedNodeEdit(command.edit, page: page, document: document,
                                        context: context, index: index,
                                        orderedNodeIDs: command.orderedNodeIDs)
        }
    }

    private func definitionEdit(
        id: ReusableStyleID, name: String, fill: CanonicalSolidColor?, opacity: Double?,
        page: DocumentPage, ownerNode: DocumentNode?, existing: CanonicalReusableStyleDefinition?
    ) throws -> PreparedDesignInspectorEdit {
        guard CanonicalReusableStyleIndex.validName(name), fill?.isValid ?? true,
              opacity.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
              fill != nil || opacity != nil else { throw AdvancedStyleCommandError.invalidValue }
        guard existing.map({ $0.name != name || $0.fill != fill || $0.opacity != opacity }) ?? true else {
            throw AdvancedStyleCommandError.noChanges
        }
        guard let root = ownerNode ?? page.rootNodeIDs.first.flatMap({ rootID in
            page.nodes.first(where: { $0.id == rootID })
        }) else {
            throw AdvancedStyleCommandError.unavailable("The active page has no stable style owner.")
        }
        let prefix = CanonicalReusableStyleIndex.namespace + "definition.\(id.description)."
        let values: [(String, PropertyValue?)] = [
            ("name", .string(name)),
            ("fill", fill.map { .string($0.hexadecimalRGBA) }),
            ("opacity", opacity.map { .number($0) }),
        ]
        var commands: [DocumentCommand] = []
        for (suffix, value) in values {
            let key = prefix + suffix
            let current = root.insertionProperty(key)
            if let value {
                if current?.value == value, current?.origin == .authored { continue }
                commands.append(.setProperty(.init(pageID: page.id, nodeID: root.id,
                    property: .init(id: current?.id ?? PropertyID(), key: .init(rawValue: key), value: value, origin: .authored))))
            } else if let current {
                commands.append(.removeProperty(.init(pageID: page.id, nodeID: root.id, propertyID: current.id)))
            }
        }
        guard !commands.isEmpty else { throw AdvancedStyleCommandError.noChanges }
        return .init(applicableNodeIDs: [root.id], skippedNodeIDs: [], skippedReasons: [:],
                     documentCommand: .batch(commands))
    }

    private func selectedNodeEdit(
        _ edit: AdvancedStyleEdit, page: DocumentPage, document: CanonicalDocument,
        context: TransformValidationContext, index: CanonicalReusableStyleIndex,
        orderedNodeIDs: [NodeID]
    ) throws -> PreparedDesignInspectorEdit {
        var applicable: [NodeID] = [], skipped: [NodeID] = [], reasons: [NodeID: String] = [:]
        var commands: [DocumentCommand] = []
        for id in orderedNodeIDs {
            guard let node = page.nodes.first(where: { $0.id == id }) else {
                throw AdvancedStyleCommandError.unavailable("A selected object no longer exists.")
            }
            guard context.availableNodeIDs.contains(id), !node.selectionBooleanProperty("hidden"),
                  !node.selectionBooleanProperty("locked") else {
                throw AdvancedStyleCommandError.unavailable("A selected object is unavailable, hidden, or locked.")
            }
            let supportsPosition = CanonicalPositioning.supportedKinds.contains(node.kind) && node.insertionGeometry != nil
                && !CanonicalPageChrome.ownsFrame(of: node, in: page)
            let supportsAppearance = Self.appearanceKinds.contains(node.kind)
            let applies: Bool
            switch edit {
            case .positionMode, .positionInset, .zIndex: applies = supportsPosition
            case .applyReusableStyles, .linkReusableStyle, .unlinkReusableStyle, .moveReusableStyle,
                 .useLinkedAppearance, .setState, .removeState: applies = supportsAppearance
            default: applies = false
            }
            guard applies else {
                skipped.append(id); reasons[id] = "This object kind does not support the selected positioning or style property."; continue
            }
            applicable.append(id)
            switch edit {
            case .positionMode(let mode):
                appendSet(key: CanonicalPositioning.namespace + "mode", value: .string(mode.rawValue), node: node, page: page, to: &commands)
                if mode == .static {
                    for edge in PositionInsetEdge.allCases { appendRemove(key: CanonicalPositioning.namespace + edge.rawValue, node: node, page: page, to: &commands) }
                }
            case .positionInset(let edge, let value):
                guard value.map({ $0.isFinite && (-1_000_000...1_000_000).contains($0) }) ?? true,
                      CanonicalPositioning.resolve(node)?.mode != .static else { throw AdvancedStyleCommandError.invalidValue }
                if let value { appendSet(key: CanonicalPositioning.namespace + edge.rawValue, value: .number(value), node: node, page: page, to: &commands) }
                else { appendRemove(key: CanonicalPositioning.namespace + edge.rawValue, node: node, page: page, to: &commands) }
            case .zIndex(let value):
                guard (-1_000_000...1_000_000).contains(value) else { throw AdvancedStyleCommandError.invalidValue }
                appendSet(key: CanonicalPositioning.namespace + "zIndex", value: .number(Double(value)), node: node, page: page, to: &commands)
            case .applyReusableStyles(let ids):
                guard ids.count <= 32, Set(ids).count == ids.count, ids.allSatisfy({ index.byID[$0] != nil }) else { throw AdvancedStyleCommandError.invalidValue }
                if ids.isEmpty { appendRemove(key: CanonicalReusableStyleIndex.appliedKey, node: node, page: page, to: &commands) }
                else { appendSet(key: CanonicalReusableStyleIndex.appliedKey, value: .string(ids.map(\.description).joined(separator: ",")), node: node, page: page, to: &commands) }
            case .linkReusableStyle(let styleID), .unlinkReusableStyle(let styleID), .moveReusableStyle(let styleID, _):
                guard index.byID[styleID] != nil else { throw AdvancedStyleCommandError.invalidValue }
                var ids = try CanonicalReusableStyleIndex.strictlyDecodedAppliedIDs(node)
                switch edit {
                case .linkReusableStyle:
                    if !ids.contains(styleID) {
                        guard ids.count < 32 else { throw AdvancedStyleCommandError.invalidValue }
                        ids.append(styleID)
                    }
                case .unlinkReusableStyle: ids.removeAll { $0 == styleID }
                case .moveReusableStyle(_, let offset):
                    guard offset == -1 || offset == 1 else { throw AdvancedStyleCommandError.invalidValue }
                    if let source = ids.firstIndex(of: styleID), ids.indices.contains(source + offset) {
                        ids.swapAt(source, source + offset)
                    }
                default: break
                }
                if ids.isEmpty { appendRemove(key: CanonicalReusableStyleIndex.appliedKey, node: node, page: page, to: &commands) }
                else { appendSet(key: CanonicalReusableStyleIndex.appliedKey,
                    value: .string(ids.map(\.description).joined(separator: ",")), node: node, page: page, to: &commands) }
            case .useLinkedAppearance(let property):
                let linked = try CanonicalReusableStyleIndex.strictlyDecodedAppliedIDs(node).compactMap { index.byID[$0] }
                switch property {
                case .fill:
                    guard linked.contains(where: { $0.fill != nil }) else {
                        throw AdvancedStyleCommandError.unavailable("Link a reusable style with a solid fill first.")
                    }
                    guard LocalColorTokenBinding.id(for: node) == nil else {
                        throw AdvancedStyleCommandError.unavailable("The fill token binding is retained. Unbind it explicitly before using a linked fill.")
                    }
                    guard CanonicalImageFill.resolve(node) == nil else {
                        throw AdvancedStyleCommandError.unavailable("Remove the image fill explicitly before using a linked solid fill.")
                    }
                    if let layers = CanonicalFillLayerCodec.layers(for: node), !layers.contains(where: \.isEnabled) {
                        throw AdvancedStyleCommandError.unavailable("Transparent / None is explicit and is not removed by reusable styling. Enable a fill explicitly before resetting it to a linked fill.")
                    }
                    guard node.insertionStringProperty("style.fill") != "none" else {
                        throw AdvancedStyleCommandError.unavailable("Explicit None is retained; enable a fill before using a linked fill.")
                    }
                    let legacy: Set<String> = ["style.fill", "style.fill.red", "style.fill.green", "style.fill.blue", "style.fill.alpha"]
                    for previous in node.properties where previous.key.rawValue.hasPrefix("style.fill.layers.v1.") || legacy.contains(previous.key.rawValue) {
                        commands.append(.removeProperty(.init(pageID: page.id, nodeID: id, propertyID: previous.id)))
                    }
                case .opacity:
                    guard linked.contains(where: { $0.opacity != nil }) else {
                        throw AdvancedStyleCommandError.unavailable("Link a reusable style with opacity first.")
                    }
                    appendRemove(key: "style.opacity", node: node, page: page, to: &commands)
                }
            case .setState(let state, let variantID, let fill, let opacity):
                guard state != .default, fill?.isValid ?? true,
                      opacity.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
                      fill != nil || opacity != nil else { throw AdvancedStyleCommandError.invalidValue }
                let prefix = CanonicalReusableStyleIndex.stateNamespace + state.rawValue + "."
                appendSet(key: prefix + "id", value: .string(variantID.uuidString.lowercased()), node: node, page: page, to: &commands)
                if let fill { appendSet(key: prefix + "fill", value: .string(fill.hexadecimalRGBA), node: node, page: page, to: &commands) }
                else { appendRemove(key: prefix + "fill", node: node, page: page, to: &commands) }
                if let opacity { appendSet(key: prefix + "opacity", value: .number(opacity), node: node, page: page, to: &commands) }
                else { appendRemove(key: prefix + "opacity", node: node, page: page, to: &commands) }
            case .removeState(let state):
                guard state != .default else { throw AdvancedStyleCommandError.invalidValue }
                let prefix = CanonicalReusableStyleIndex.stateNamespace + state.rawValue + "."
                for suffix in ["id", "fill", "opacity"] { appendRemove(key: prefix + suffix, node: node, page: page, to: &commands) }
            default: throw AdvancedStyleCommandError.invalidValue
            }
        }
        guard !applicable.isEmpty else { throw AdvancedStyleCommandError.unavailable("The selection has no applicable objects.") }
        guard !commands.isEmpty else { throw AdvancedStyleCommandError.noChanges }
        return .init(applicableNodeIDs: applicable, skippedNodeIDs: skipped, skippedReasons: reasons,
                     documentCommand: .batch(commands))
    }

    private func appendSet(key: String, value: PropertyValue, node: DocumentNode, page: DocumentPage,
                           to commands: inout [DocumentCommand]) {
        let existing = node.insertionProperty(key)
        guard existing?.value != value || existing?.origin != .authored else { return }
        commands.append(.setProperty(.init(pageID: page.id, nodeID: node.id,
            property: .init(id: existing?.id ?? PropertyID(), key: .init(rawValue: key), value: value, origin: .authored))))
    }

    private func appendRemove(key: String, node: DocumentNode, page: DocumentPage,
                              to commands: inout [DocumentCommand]) {
        guard let existing = node.insertionProperty(key) else { return }
        commands.append(.removeProperty(.init(pageID: page.id, nodeID: node.id, propertyID: existing.id)))
    }

    private func definitionOwner(id: ReusableStyleID, in document: CanonicalDocument) -> (pageID: PageID, node: DocumentNode)? {
        let prefix = CanonicalReusableStyleIndex.namespace + "definition.\(id.description)."
        for page in document.pages {
            if let node = page.nodes.first(where: { $0.properties.contains(where: { $0.key.rawValue.hasPrefix(prefix) }) }) {
                return (page.id, node)
            }
        }
        return nil
    }
}

enum AdvancedStyleDiagnosticResult: String, Codable, Sendable {
    case success, failure, cancelled, stale
}

struct AdvancedStyleDiagnosticRecord: Codable, Equatable, Sendable {
    let requirementIDs: [String]
    let operationType: String
    let provenance: DesignInspectorProvenance
    let sanitizedIdentifiers: [String]
    let durationMilliseconds: Double
    let parentRevision: UInt64
    let resultRevision: UInt64?
    let result: AdvancedStyleDiagnosticResult
    let failureCategory: String?
}

actor AdvancedStyleDiagnostics {
    private var buffer = BoundedDiagnosticBuffer<AdvancedStyleDiagnosticRecord>()
    func append(_ record: AdvancedStyleDiagnosticRecord) { buffer.append(record) }
    func snapshot() -> [AdvancedStyleDiagnosticRecord] { buffer.snapshot() }
    func droppedRecordCount() -> UInt64 { buffer.droppedRecordCount }
}

enum AdvancedStyleDiagnosticFactory {
    static func make(
        command: AdvancedStyleCommand,
        durationMilliseconds: Double = 0,
        resultRevision: UInt64?,
        result: AdvancedStyleDiagnosticResult,
        failure: AdvancedStyleCommandError?
    ) -> AdvancedStyleDiagnosticRecord {
        .init(
            requirementIDs: AdvancedStyleCommandRegistry.requirementIDs.sorted(),
            operationType: operationType(command.edit),
            provenance: command.provenance,
            sanitizedIdentifiers: command.orderedNodeIDs.map {
                DiagnosticStableIdentifier.sanitize($0.description, domain: .advancedStyle, kind: "node")
            },
            durationMilliseconds: max(0, durationMilliseconds),
            parentRevision: command.identity.revision,
            resultRevision: resultRevision,
            result: result,
            failureCategory: failure.map(category)
        )
    }

    private static func operationType(_ edit: AdvancedStyleEdit) -> String {
        switch edit {
        case .positionMode: "position.mode"
        case .positionInset: "position.inset"
        case .zIndex: "position.z-index"
        case .createReusableStyle: "reusable.create"
        case .updateReusableStyle: "reusable.update"
        case .removeReusableStyle: "reusable.remove"
        case .applyReusableStyles: "reusable.apply"
        case .linkReusableStyle: "reusable.link"
        case .unlinkReusableStyle: "reusable.unlink"
        case .moveReusableStyle: "reusable.reorder"
        case .useLinkedAppearance(let property): "reusable.inherit.\(property.rawValue)"
        case .setState(let state, _, _, _): "state.\(state.rawValue).set"
        case .removeState(let state): "state.\(state.rawValue).remove"
        }
    }

    private static func category(_ error: AdvancedStyleCommandError) -> String {
        switch error {
        case .stale: "stale-identity"
        case .cancelled: "cancelled"
        case .invalidValue: "invalid-value"
        case .noSelection: "no-selection"
        case .duplicateTarget: "duplicate-target"
        case .unavailable: "unavailable"
        case .noChanges: "no-changes"
        }
    }
}

/// SF-0509: a token reference decorates the existing solid layer. The layer
/// remains the explicit literal fallback, so a missing token never destroys
/// authored color intent and unbinding can preserve the resolved appearance.
enum LocalColorTokenResolver {
    static func textForeground(for node: DocumentNode, tokens: [LocalColorToken]) -> CanonicalSolidColor? {
        let literal = CanonicalTextForeground.literal(for: node)
        guard let id = LocalColorTokenBinding.id(for: node, target: .textForeground),
              let token = tokens.first(where: { $0.id == id }) else { return literal }
        return token.color
    }
    static func resolvedBoxStyle(for node: DocumentNode, tokens: [LocalColorToken]) -> CanonicalBoxStyle? {
        guard let style = DesignBoxStyleCommandRegistry.resolvedStyle(for: node) else { return nil }
        func color(_ target: LocalColorTarget, fallback: CanonicalSolidColor) -> CanonicalSolidColor {
            guard let id = LocalColorTokenBinding.id(for: node, target: target),
                  let token = tokens.first(where: { $0.id == id }) else { return fallback }
            return token.color
        }
        let border = style.border.map {
            CanonicalBorder(color: color(.border, fallback: $0.color), width: $0.width, style: $0.style)
        }
        let shadow = style.shadow.map {
            CanonicalShadow(color: color(.outerShadow, fallback: $0.color), offsetX: $0.offsetX,
                offsetY: $0.offsetY, blur: $0.blur, spread: $0.spread)
        }
        return CanonicalBoxStyle(border: border, cornerRadius: style.cornerRadius, shadow: shadow,
            shadowEnabled: style.shadowEnabled, padding: style.padding, clipsContent: style.clipsContent)
    }

    static func fillValue(nodes: [DocumentNode], in document: CanonicalDocument) -> DesignInspectorValue {
        let applicable = nodes.filter { DesignInspectorCommandRegistry.fillKinds.contains($0.kind) }
        guard !applicable.isEmpty else {
            return .unavailable("Select a Frame, Section, Stack, or Grid to edit its fill.")
        }
        let values = applicable.map { node -> (CanonicalSolidColor?, PropertyOrigin) in
            let literal = DesignInspectorCommandRegistry.resolvedFill(for: node)
            guard literal.0 != nil,
                  let tokenID = LocalColorTokenBinding.id(for: node),
                  let token = document.colorTokens.first(where: { $0.id == tokenID }) else { return literal }
            return (token.color, .authored)
        }
        guard let first = values.first, values.contains(where: { $0.0 != nil }) else {
            return .unavailable("No solid fill is applied.")
        }
        guard values.allSatisfy({ $0.0 == first.0 }) else { return .mixed }
        guard let color = first.0 else { return .unavailable("No solid fill is applied.") }
        return .single(color, first.1)
    }

    static func resolvedLayers(for node: DocumentNode, in document: CanonicalDocument) -> [CanonicalFillLayer] {
        resolvedLayers(for: node, tokens: document.colorTokens)
    }

    static func resolvedLayers(for node: DocumentNode, tokens: [LocalColorToken]) -> [CanonicalFillLayer] {
        let layers = DesignInspectorCommandRegistry.resolvedLayers(for: node)
        guard let tokenID = LocalColorTokenBinding.id(for: node),
              let token = tokens.first(where: { $0.id == tokenID }),
              let index = layers.lastIndex(where: { $0.kind == .solid && $0.isEnabled }) else { return layers }
        var result = layers
        result[index] = .solid(id: result[index].id, color: token.color, isEnabled: true)
        return result
    }

    static func status(for node: DocumentNode, in document: CanonicalDocument,
                       target: LocalColorTarget = .fill) -> String? {
        guard let id = LocalColorTokenBinding.id(for: node, target: target) else { return nil }
        guard let token = document.colorTokens.first(where: { $0.id == id }) else {
            return "Missing color token · literal fallback retained"
        }
        return "\(target.displayName) token: \(token.name) / \(token.color.hexadecimalRGBA)"
    }
}

enum LocalColorTokenEdit: Sendable {
    case create(name: String, color: CanonicalSolidColor)
    case update(ColorTokenID, name: String, color: CanonicalSolidColor)
    case rename(ColorTokenID, String)
    case recolor(ColorTokenID, CanonicalSolidColor)
    case delete(ColorTokenID)
    case bind(ColorTokenID)
    case unbind
    case bindTarget(ColorTokenID, LocalColorTarget)
    case unbindTarget(LocalColorTarget)
}

enum LocalColorTokenCommandError: Error, LocalizedError {
    case stale, cancelled, invalid, conflict, inUse(Int), unavailable(String), unchanged
    var errorDescription: String? {
        switch self {
        case .stale: "The color-token edit is stale; project colors are unchanged."
        case .cancelled: "The color-token draft was cancelled."
        case .invalid: "Enter a unique token name and a complete #RRGGBB or #RRGGBBAA color."
        case .conflict: "A color token already uses that name."
        case .inUse(let count): "This token is used by \(count) object\(count == 1 ? "" : "s"). Unbind those objects before deleting it."
        case .unavailable(let reason): reason
        case .unchanged: "The color-token value is unchanged."
        }
    }
}

struct LocalColorTokenCommandRegistry {
    static func prepare(
        _ edit: LocalColorTokenEdit, in document: CanonicalDocument,
        expectedDocumentID: DocumentID, expectedRevision: UInt64,
        pageID: PageID?, selectedNodeIDs: [NodeID] = [],
        cancelled: Bool = false
    ) throws -> DocumentCommand {
        guard !cancelled else { throw LocalColorTokenCommandError.cancelled }
        guard document.id == expectedDocumentID, document.revision == expectedRevision,
              document.revision < UInt64.max else { throw LocalColorTokenCommandError.stale }
        var tokens = document.colorTokens
        switch edit {
        case .create(let name, let color):
            guard valid(name, color: color) else { throw LocalColorTokenCommandError.invalid }
            guard !tokens.contains(where: { equalNames($0.name, name) }) else { throw LocalColorTokenCommandError.conflict }
            tokens.append(.init(name: name, color: color))
        case .update(let id, let name, let color):
            guard let index = tokens.firstIndex(where: { $0.id == id }) else { throw LocalColorTokenCommandError.stale }
            guard valid(name, color: color) else { throw LocalColorTokenCommandError.invalid }
            guard !tokens.contains(where: { $0.id != id && equalNames($0.name, name) }) else { throw LocalColorTokenCommandError.conflict }
            tokens[index].name = name; tokens[index].color = color
        case .rename(let id, let name):
            guard let index = tokens.firstIndex(where: { $0.id == id }) else { throw LocalColorTokenCommandError.stale }
            guard valid(name, color: tokens[index].color) else { throw LocalColorTokenCommandError.invalid }
            guard !tokens.contains(where: { $0.id != id && equalNames($0.name, name) }) else { throw LocalColorTokenCommandError.conflict }
            tokens[index].name = name
        case .recolor(let id, let color):
            guard let index = tokens.firstIndex(where: { $0.id == id }) else { throw LocalColorTokenCommandError.stale }
            guard color.isValid else { throw LocalColorTokenCommandError.invalid }
            tokens[index].color = color
        case .delete(let id):
            guard tokens.contains(where: { $0.id == id }) else { throw LocalColorTokenCommandError.stale }
            let uses = document.pages.flatMap(\.nodes).reduce(0) { count, node in
                count + LocalColorTarget.allCases.filter { LocalColorTokenBinding.id(for: node, target: $0) == id }.count
            }
            guard uses == 0 else { throw LocalColorTokenCommandError.inUse(uses) }
            tokens.removeAll { $0.id == id }
        case .bind(let id):
            guard tokens.contains(where: { $0.id == id }) else { throw LocalColorTokenCommandError.stale }
            return try bindingCommands(document: document, pageID: pageID, ids: selectedNodeIDs, tokenID: id, target: .fill)
        case .unbind:
            return try bindingCommands(document: document, pageID: pageID, ids: selectedNodeIDs, tokenID: nil, target: .fill)
        case .bindTarget(let id, let target):
            guard tokens.contains(where: { $0.id == id }) else { throw LocalColorTokenCommandError.stale }
            return try bindingCommands(document: document, pageID: pageID, ids: selectedNodeIDs, tokenID: id, target: target)
        case .unbindTarget(let target):
            return try bindingCommands(document: document, pageID: pageID, ids: selectedNodeIDs, tokenID: nil, target: target)
        }
        guard tokens != document.colorTokens else { throw LocalColorTokenCommandError.unchanged }
        return .setColorTokens(.init(tokens: tokens))
    }

    private static func bindingCommands(document: CanonicalDocument, pageID: PageID?, ids: [NodeID],
                                        tokenID: ColorTokenID?, target: LocalColorTarget) throws -> DocumentCommand {
        guard let pageID, let page = document.pages.first(where: { $0.id == pageID }),
              !ids.isEmpty, Set(ids).count == ids.count else { throw LocalColorTokenCommandError.stale }
        var commands: [DocumentCommand] = []
        var applicableCount = 0
        for id in ids {
            guard let node = page.nodes.first(where: { $0.id == id }) else { throw LocalColorTokenCommandError.stale }
            guard !node.selectionBooleanProperty("hidden"), !node.selectionBooleanProperty("locked") else {
                throw LocalColorTokenCommandError.unavailable("A selected object is hidden or locked.")
            }
            let style = DesignBoxStyleCommandRegistry.resolvedStyle(for: node)
            let supported: Bool = switch target {
            case .fill: [.frame, .section, .stack, .grid].contains(node.kind)
                && DesignInspectorCommandRegistry.resolvedLayers(for: node).contains(where: { $0.kind == .solid && $0.isEnabled })
            case .border: style?.border != nil
            case .outerShadow: style?.shadow != nil
            case .textForeground: node.kind.isTextual && CanonicalTextForeground.literal(for: node) != nil
            }
            guard supported else { continue }
            applicableCount += 1
            let bindingKey = LocalColorTokenBinding.key(for: target)
            let old = node.insertionProperty(bindingKey)
            if let tokenID {
                guard LocalColorTokenBinding.id(for: node, target: target) != tokenID else { continue }
                commands.append(.setProperty(.init(pageID: pageID, nodeID: id, property: .init(
                    id: old?.id ?? PropertyID(), key: .init(rawValue: bindingKey),
                    value: .string(tokenID.description), origin: .authored))))
            } else if let old {
                if target != .fill {
                    let literal: CanonicalSolidColor? = switch target {
                    case .border: style?.border?.color
                    case .outerShadow: style?.shadow?.color
                    case .textForeground: CanonicalTextForeground.literal(for: node)
                    case .fill: nil
                    }
                    let resolved = LocalColorTokenResolver.resolvedBoxStyle(for: node, tokens: document.colorTokens)
                    let color: CanonicalSolidColor? = switch target {
                    case .border: resolved?.border?.color
                    case .outerShadow: resolved?.shadow?.color
                    case .textForeground: LocalColorTokenResolver.textForeground(for: node, tokens: document.colorTokens)
                    case .fill: nil
                    }
                    if let literal, let color, literal != color {
                        let prefix = target == .textForeground ? CanonicalTextForeground.prefix
                            : DesignBoxStyleCommandRegistry.namespace
                                + (target == .border ? "border.color." : "shadow.color.")
                        for (channel, number) in [("red", color.red), ("green", color.green),
                                                  ("blue", color.blue), ("alpha", color.alpha)] {
                            let previous = node.insertionProperty(prefix + channel)
                            guard let previous else { throw LocalColorTokenCommandError.stale }
                            commands.append(.setProperty(.init(pageID: pageID, nodeID: id,
                                property: .init(id: previous.id, key: previous.key,
                                    value: .number(number), origin: .authored))))
                        }
                    }
                }
                if target == .fill, let resolved = LocalColorTokenResolver.resolvedLayers(for: node, in: document).last(where: { $0.kind == .solid && $0.isEnabled }),
                   let color = resolved.solidColor,
                   let original = DesignInspectorCommandRegistry.resolvedLayers(for: node).last(where: { $0.kind == .solid && $0.isEnabled }),
                   original.solidColor != color {
                    if CanonicalFillLayerCodec.layers(for: node) != nil {
                        let prefix = "style.fill.layers.v1.\(original.id.description)."
                        for (channel, number) in [("red", color.red), ("green", color.green), ("blue", color.blue), ("alpha", color.alpha)] {
                            let key = prefix + channel
                            let previous = node.insertionProperty(key)
                            commands.append(.setProperty(.init(pageID: pageID, nodeID: id, property: .init(
                                id: previous?.id ?? PropertyID(), key: .init(rawValue: key), value: .number(number), origin: .authored))))
                        }
                    } else {
                        let next = DesignInspectorCommandRegistry.resolvedLayers(for: node).map { layer in
                            layer.id == original.id ? CanonicalFillLayer.solid(id: layer.id, color: color, isEnabled: layer.isEnabled) : layer
                        }
                        for (key, value) in CanonicalFillLayerCodec.propertyValues(for: next).sorted(by: { $0.key < $1.key }) {
                            commands.append(.setProperty(.init(pageID: pageID, nodeID: id, property: .init(
                                key: .init(rawValue: key), value: value, origin: .authored))))
                        }
                        for property in node.properties where ["style.fill", "style.fill.red", "style.fill.green", "style.fill.blue", "style.fill.alpha"].contains(property.key.rawValue) {
                            commands.append(.removeProperty(.init(pageID: pageID, nodeID: id, propertyID: property.id)))
                        }
                    }
                }
                commands.append(.removeProperty(.init(pageID: pageID, nodeID: id, propertyID: old.id)))
            }
        }
        guard applicableCount > 0 else {
            throw LocalColorTokenCommandError.unavailable("The selection has no applicable \(target.rawValue) color.")
        }
        guard !commands.isEmpty else { throw LocalColorTokenCommandError.unchanged }
        return .batch(commands)
    }

    private static func valid(_ name: String, color: CanonicalSolidColor) -> Bool {
        LocalColorToken(name: name, color: color).isValid
    }
    private static func equalNames(_ lhs: String, _ rhs: String) -> Bool {
        lhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) == rhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
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

struct TransformValidationContext: Equatable, Sendable {
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

/// Scene-local edit ownership, not canonical responsive content. Revision is
/// deliberately absent: unrelated adoption may refresh the command identity,
/// but changing selection, page, breakpoint or free viewport width may not.
struct LayoutInspectorDraftScope: Equatable, Sendable {
    let documentID: DocumentID
    let pageID: PageID?
    let sceneID: CanvasViewportSceneID
    let orderedNodeIDs: [NodeID]
    let breakpoint: ResponsiveBreakpoint
    let viewportWidth: Double
}

/// Captured event/draft ownership. Unlike numeric fallback adoption, a fluid
/// range or visibility action must not be replayed against a later revision.
/// This is scene-local UI context, never a serialized responsive property.
struct ResponsiveInspectorEditContext: Equatable, Sendable {
    let scope: LayoutInspectorDraftScope
    let revision: UInt64
}

/// Availability validates a prospective canonical transaction, not an inline
/// text draft. Reuse that result only while every command-owning input agrees;
/// actual commits still go through the registry's full validation.
struct WorkspaceAvailabilityCache<Key: Equatable, Operation: Equatable, Value> {
    private var key: Key?
    private var values: [(Operation, Value)] = []
    private let capacity: Int

    init(capacity: Int = 32) { self.capacity = max(1, min(256, capacity)) }

    mutating func resolve(_ operation: Operation, key newKey: Key, prepare: () -> Value) -> Value {
        if key != newKey { key = newKey; values.removeAll(keepingCapacity: true) }
        if let value = values.first(where: { $0.0 == operation })?.1 { return value }
        let value = prepare()
        if values.count == capacity { values.removeFirst() }
        values.append((operation, value))
        return value
    }
}

struct GeometryInspectorAvailabilityCache {
    struct Key: Equatable {
        let scope: LayoutInspectorDraftScope
        let revision: UInt64
        let renderer: CanvasRenderRequestIdentity
        let context: TransformValidationContext
    }
    private var cache = WorkspaceAvailabilityCache<Key, GeometryInspectorField, TransformAvailability>()

    mutating func resolve(_ field: GeometryInspectorField, key newKey: Key,
                          prepare: () -> TransformAvailability) -> TransformAvailability {
        cache.resolve(field, key: newKey, prepare: prepare)
    }
}

enum InspectorDraftAccessibility {
    /// Do not announce a committed number as the value of an unfinished editor.
    /// Canonical geometry/provenance remains available in the Inspector summary.
    static func value(draft: String?, committed: String) -> String {
        guard let draft else { return committed }
        return "\(draft.isEmpty ? "Empty" : draft); uncommitted draft"
    }
}

struct LayoutInspectorNumericDraft: Equatable, Sendable {
    enum Conflict: Equatable, Sendable { case contextChanged, valueChanged }
    var text: String
    private(set) var committed: String
    let scope: LayoutInspectorDraftScope
    private(set) var conflict: Conflict?
    var hasUnchangedNumericValue: Bool {
        guard conflict == nil else { return false }
        if text == committed { return true }
        guard case .success(let current) = GeometryInspectorNumberParser.parse(text),
              case .success(let original) = GeometryInspectorNumberParser.parse(committed) else { return false }
        return current == original
    }
    init(text: String, committed: String, scope: LayoutInspectorDraftScope) {
        self.text = text; self.committed = committed; self.scope = scope
    }
    mutating func adopt(committed next: String?, scope nextScope: LayoutInspectorDraftScope) {
        guard scope == nextScope else { conflict = .contextChanged; return }
        // A renderer being replaced has no current computed number yet. That
        // is not an external edit to the field's last committed value.
        guard let next else { return }
        if next != committed && next != text { conflict = .valueChanged }
        committed = next
    }
    func canCommit(in currentScope: LayoutInspectorDraftScope) -> Bool {
        scope == currentScope && conflict == nil
    }
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
    case computed(value: Double, source: String)
    case mixed
}

/// SF-0702/0703: closed property-value clipboard, not an executable command or
/// a second property store. Resolved source numbers become explicit destination
/// values; source IDs, provenance and breakpoint ownership are never copied.
struct InspectorGeometryTransfer: Equatable, Sendable {
    static let maximumBytes = 2048
    let field: GeometryInspectorField
    let value: Double
    private struct Wire: Codable { let version: Int; let field: String; let value: Double }
    func encoded() throws -> Data {
        guard GeometryInspectorCommandRegistry.isValid(value, for: field) else { throw GeometryInspectorError.invalidValue }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Wire(version: 1, field: field.rawValue, value: value == 0 ? 0 : value))
    }
    static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= maximumBytes,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              Set(object.keys) == Set(["version", "field", "value"]),
              let wire = try? JSONDecoder().decode(Wire.self, from: data), wire.version == 1,
              let field = GeometryInspectorField(rawValue: wire.field),
              GeometryInspectorCommandRegistry.isValid(wire.value, for: field) else {
            throw GeometryInspectorError.invalidValue
        }
        let transfer = Self(field: field, value: wire.value)
        // This private clipboard flavor accepts only the deterministic encoding
        // written above: duplicate keys, alternate numeric forms and hidden
        // trailing/unknown content cannot acquire ambiguous interpretation.
        guard try transfer.encoded() == data else { throw GeometryInspectorError.invalidValue }
        return transfer
    }
    func prepare(identity: GeometryInspectorOperationIdentity, orderedNodeIDs: [NodeID],
                 document: CanonicalDocument, context: TransformValidationContext,
                 breakpoint: ResponsiveBreakpoint, cancellation: TransformCancellation = .never) throws -> PreparedGeometryInspectorEdit {
        try GeometryInspectorCommandRegistry().prepare(.init(identity: identity, orderedNodeIDs: orderedNodeIDs,
            field: field, value: value, provenance: .keyboard, breakpoint: breakpoint),
            in: document, context: context, cancellation: cancellation)
    }
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

    private static let supportedKinds: Set<NodeKind> = [.frame, .text, .section, .stack, .grid, .image, .button, .link, .component]

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
            .filter { !CanonicalPageFlow.isNavigationLink($0) && (CanonicalPageFlow.role($0) == nil || field == .height) }
            .filter { node in
                guard let page = document.pages.first(where: { $0.id == context.activePageID }) else { return false }
                return !CanonicalPageChrome.ownsFrame(of: node, in: page)
            }
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
        let geometryNodesByID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let automaticSizing = page.hasAutomaticSizing
        for id in command.orderedNodeIDs {
            guard !cancellation.isCancelled() else { throw GeometryInspectorError.cancelled }
            guard let node = geometryNodesByID[id] else {
                throw GeometryInspectorError.missingTarget
            }
            guard Self.supportsFixedGeometry(node.kind) else {
                skipped.append(id)
                continue
            }
            if CanonicalPageChrome.ownsFrame(of: node, in: page) || CanonicalPageFlow.isNavigationLink(node)
                || (CanonicalPageFlow.role(node) != nil && command.field != .height) {
                skipped.append(id); continue
            }
            guard !node.insertionBooleanProperty("locked") else { throw GeometryInspectorError.lockedTarget }
            guard !node.insertionBooleanProperty("hidden") else { throw GeometryInspectorError.hiddenTarget }
            guard context.availableNodeIDs.contains(id) else { throw GeometryInspectorError.unavailableTarget }
            if command.breakpoint == .desktop {
                if automaticSizing, CanonicalSizingConstraints.isLayoutResolved(command.field, node: node, page: page,
                    breakpoint: .desktop, width: nil, nodesByID: geometryNodesByID) { skipped.append(id); continue }
                guard !command.removesOverride,
                      let property = node.insertionProperty(command.field.propertyKey) else { skipped.append(id); continue }
                if [.frame, .image].contains(node.kind),
                   command.field == .width || command.field == .height,
                   let frame = node.insertionGeometry?.frame {
                    let sizing = CanonicalSizingConstraints.resolved(for: node)
                    let adjusted: (width: Double, height: Double)
                    do {
                        adjusted = try SizingConstraintPolicy.adjusted(
                            width: command.field == .width ? command.value : frame.size.width,
                            height: command.field == .height ? command.value : frame.size.height,
                            constraints: sizing, driver: command.field == .width ? .width : .height)
                    } catch { throw GeometryInspectorError.invalidValue }
                    for (field, value) in [(GeometryInspectorField.width, adjusted.width), (.height, adjusted.height)] {
                        guard let dimension = node.insertionProperty(field.propertyKey) else { throw GeometryInspectorError.invalidValue }
                        commands.append(.setProperty(.init(pageID: page.id, nodeID: id,
                            property: .init(id: dimension.id, key: dimension.key,
                                value: .number(value), origin: .authored))))
                    }
                } else {
                    commands.append(.setProperty(.init(pageID: page.id, nodeID: id,
                        property: .init(id: property.id, key: property.key, value: .number(command.value), origin: .authored))))
                }
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

enum SizingConstraintField: String, CaseIterable, Sendable {
    case minWidth, minHeight, maxWidth, maxHeight, aspectRatio
    var title: String {
        switch self {
        case .minWidth: "Min width"
        case .minHeight: "Min height"
        case .maxWidth: "Max width"
        case .maxHeight: "Max height"
        case .aspectRatio: "Aspect ratio"
        }
    }
}

enum SizingConstraintPresentation: Equatable, Sendable {
    case unavailable(String)
    case mixed
    case single(Double?, PropertyOrigin)
}

enum SizingConstraintEdit: Sendable {
    case set(SizingConstraintField, Double?)
    case setAspectEnabled(Bool)
    case setMode(SizingDimension, CanonicalSizingMode)
    case convertContent
    case reset
}

struct SizingConstraintCommand: Sendable {
    let identity: GeometryInspectorOperationIdentity
    let orderedNodeIDs: [NodeID]
    let edit: SizingConstraintEdit
    let cancelled: Bool
    var breakpoint: ResponsiveBreakpoint = .desktop
}

enum SizingConstraintError: Error, LocalizedError {
    case stale, cancelled, invalid, unavailable, unchanged
    var errorDescription: String? {
        switch self {
        case .stale: "Sizing changed before the edit could commit. Try again."
        case .cancelled: "Sizing draft cancelled; geometry is unchanged."
        case .invalid: "Use compatible Fixed/Fill/Hug modes and finite bounds. Minimum cannot exceed maximum; aspect lock requires fixed dimensions. A flow container cannot hug a fill-height child."
        case .unavailable: "Select an unlocked, visible object with applicable base sizing. Managed navigation and breakpoint overrides remain separate."
        case .unchanged: "Sizing is already at the requested value."
        }
    }
}

enum SizingConstraintPolicy {
    enum Driver { case width, height }
    static func adjusted(width: Double, height: Double, constraints: CanonicalSizingConstraints,
                         driver: Driver) throws -> (width: Double, height: Double) {
        guard constraints.isValid, width.isFinite, height.isFinite else { throw SizingConstraintError.invalid }
        let minimum = TransformPolicy.minimumDimension
        let lowW = max(minimum, constraints.minWidth ?? minimum)
        let lowH = max(minimum, constraints.minHeight ?? minimum)
        let highW = min(LayoutPolicy.maximumDimension, constraints.maxWidth ?? LayoutPolicy.maximumDimension)
        let highH = min(LayoutPolicy.maximumDimension, constraints.maxHeight ?? LayoutPolicy.maximumDimension)
        guard lowW <= highW, lowH <= highH else { throw SizingConstraintError.invalid }
        if constraints.aspectEnabled, let ratio = constraints.aspectRatio {
            let lowerWidth = max(lowW, lowH * ratio)
            let upperWidth = min(highW, highH * ratio)
            guard lowerWidth <= upperWidth else { throw SizingConstraintError.invalid }
            let requestedWidth = driver == .width ? width : height * ratio
            let clampedWidth = min(upperWidth, max(lowerWidth, requestedWidth))
            return (clampedWidth, clampedWidth / ratio)
        }
        return (min(highW, max(lowW, width)), min(highH, max(lowH, height)))
    }
}

struct SizingConstraintCommandRegistry {
    struct ConversionScope: Equatable, Sendable {
        let applicableNodeIDs: [NodeID]
        let skippedNodeIDs: [NodeID]
        let removedDimensionPropertyCount: Int
    }

    static func supportsMode(_ dimension: SizingDimension, _ mode: CanonicalSizingMode,
                             node: DocumentNode, page: DocumentPage) -> Bool {
        CanonicalSizingConstraints.supportedKinds.contains(node.kind)
            && !(dimension == .width && mode == .hug)
            && !(node.kind == .image && mode == .hug)
            && !(dimension == .width && CanonicalPageFlow.role(node) != nil)
            && CanonicalPageFlow.role(node) != .header && CanonicalPageFlow.role(node) != .footer
            && !CanonicalPageChrome.ownsFrame(of: node, in: page)
            && !CanonicalPageFlow.isNavigationLink(node)
            && (mode == .fixed || !CanonicalSizingConstraints.resolved(for: node).aspectEnabled)
    }

    private static func convertible(_ node: DocumentNode, page: DocumentPage,
                                    context: TransformValidationContext) -> Bool {
        CanonicalSizingConstraints.supportedKinds.contains(node.kind)
            && !CanonicalPageChrome.ownsFrame(of: node, in: page) && !CanonicalPageFlow.isNavigationLink(node)
            && node.kind != .image && !node.kind.isLinkControl && node.insertionGeometry != nil
            && !node.insertionBooleanProperty("locked") && !node.insertionBooleanProperty("hidden")
            && context.availableNodeIDs.contains(node.id) && !CanonicalSizingConstraints.resolved(for: node).aspectEnabled
            && CanonicalPageFlow.role(node) != .header && CanonicalPageFlow.role(node) != .footer
            && (node.kind != .frame || !node.childIDs.isEmpty)
    }

    static func conversionScope(page: DocumentPage, context: TransformValidationContext) -> ConversionScope {
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        var pending = context.selectedNodeIDs, visited = Set<NodeID>()
        while let id = pending.popLast() {
            guard visited.insert(id).inserted, let node = byID[id] else { continue }
            pending += node.childIDs
        }
        let nodes = page.canonicalDepthFirstNodes().filter { visited.contains($0.id) }
        let applicable = nodes.filter { convertible($0, page: page, context: context) }
        let keys = Set(ResponsiveBreakpoint.allCases.flatMap { breakpoint in
            [ResponsiveGeometryResolver.key(.width, breakpoint: breakpoint), ResponsiveGeometryResolver.key(.height, breakpoint: breakpoint)]
        } + [CanonicalFluidValueCodec.key(.width), CanonicalFluidValueCodec.key(.height)])
        return .init(applicableNodeIDs: applicable.map(\.id),
            skippedNodeIDs: nodes.filter { !convertible($0, page: page, context: context) }.map(\.id),
            removedDimensionPropertyCount: applicable.reduce(0) { $0 + $1.properties.filter { keys.contains($0.key.rawValue) }.count })
    }

    /// Compile an exact winning-dimension reset through the existing geometry
    /// or fluid registry; never clear sibling dimensions or inherited literals.
    func prepareDimensionReset(_ dimension: SizingDimension, source: ResponsiveGeometrySource,
        identity: GeometryInspectorOperationIdentity, orderedNodeIDs: [NodeID], breakpoint: ResponsiveBreakpoint,
        in document: CanonicalDocument, context: TransformValidationContext, cancelled: Bool = false) throws -> DocumentCommand {
        guard !cancelled else { throw SizingConstraintError.cancelled }
        guard let page = document.pages.first(where: { $0.id == context.activePageID }) else { throw SizingConstraintError.stale }
        let nodes = try orderedNodeIDs.map { id -> DocumentNode in
            guard let node = page.nodes.first(where: { $0.id == id }) else { throw SizingConstraintError.stale }
            return node
        }.filter { CanonicalSizingConstraints.supportedKinds.contains($0.kind) }
        guard !nodes.isEmpty, nodes.allSatisfy({ CanonicalSizingConstraints.dimensionResolution(dimension,
            node: $0, breakpoint: breakpoint, width: nil).numericSource == source }) else { throw SizingConstraintError.invalid }
        switch source {
        case .override(let owner):
            guard owner == breakpoint, breakpoint != .desktop else { throw SizingConstraintError.invalid }
            return try GeometryInspectorCommandRegistry().prepare(.init(identity: identity, orderedNodeIDs: orderedNodeIDs,
                field: dimension == .width ? .width : .height, value: 0, provenance: .pointer,
                breakpoint: breakpoint, removesOverride: true), in: document, context: context).documentCommand
        case .fluid:
            return try FluidValueCommandRegistry().prepare(.init(identity: identity, orderedNodeIDs: orderedNodeIDs,
                target: dimension == .width ? .width : .height, value: nil, provenance: .pointer, cancelled: false),
                in: document, context: context).documentCommand
        case .baseDesktop: throw SizingConstraintError.unavailable
        }
    }
    struct Prepared: Sendable {
        let documentCommand: DocumentCommand
        let applicableNodeIDs: [NodeID]
        let skippedNodeIDs: [NodeID]
    }

    func prepare(_ command: SizingConstraintCommand, in document: CanonicalDocument,
                 context: TransformValidationContext) throws -> Prepared {
        guard !command.cancelled else { throw SizingConstraintError.cancelled }
        guard command.breakpoint == .desktop else { throw SizingConstraintError.unavailable }
        guard context.isLifecycleAvailable,
              command.identity.documentID == document.id,
              command.identity.revision == document.revision,
              command.identity.pageID == context.activePageID,
              command.identity.sceneID == context.currentSceneID,
              command.identity.rendererGeneration == context.rendererGeneration,
              command.orderedNodeIDs == context.selectedNodeIDs,
              Set(command.orderedNodeIDs).count == command.orderedNodeIDs.count,
              document.revision < UInt64.max,
              let page = document.pages.first(where: { $0.id == context.activePageID }) else {
            throw SizingConstraintError.stale
        }
        var changes: [DocumentCommand] = [], applicable: [NodeID] = [], skipped: [NodeID] = []
        let conversion: Bool = if case .convertContent = command.edit { true } else { false }
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let targets: [NodeID]
        if conversion {
            var pending = command.orderedNodeIDs, visited = Set<NodeID>()
            while let id = pending.popLast() {
                guard visited.insert(id).inserted else { continue }
                guard let node = byID[id] else { throw SizingConstraintError.stale }
                pending.append(contentsOf: node.childIDs)
            }
            targets = page.canonicalDepthFirstNodes().map(\.id).filter(visited.contains)
        } else { targets = command.orderedNodeIDs }
        for id in targets {
            guard let node = byID[id] else { throw SizingConstraintError.stale }
            guard CanonicalSizingConstraints.supportedKinds.contains(node.kind) else { skipped.append(id); continue }
            switch command.edit {
            case .set, .setAspectEnabled:
                guard CanonicalSizingConstraints.boundsSupportedKinds.contains(node.kind) else { skipped.append(id); continue }
            case .setMode, .reset, .convertContent: break
            }
            guard !CanonicalPageChrome.ownsFrame(of: node, in: page),
                  !CanonicalPageFlow.isNavigationLink(node) else { skipped.append(id); continue }
            if conversion {
                guard Self.convertible(node, page: page, context: context) else { skipped.append(id); continue }
            }
            if case .setMode(let dimension, let mode) = command.edit {
                guard !(dimension == .width && mode == .hug) else { throw SizingConstraintError.invalid }
                guard Self.supportsMode(dimension, mode, node: node, page: page) else { skipped.append(id); continue }
            }
            guard !node.insertionBooleanProperty("locked"), !node.insertionBooleanProperty("hidden"),
                  context.availableNodeIDs.contains(id), let frame = node.insertionGeometry?.frame else {
                throw SizingConstraintError.unavailable
            }
            applicable.append(id)
            var next = CanonicalSizingConstraints.resolved(for: node)
            var updates: [(String, PropertyValue?)] = []
            let driver: SizingConstraintPolicy.Driver
            switch command.edit {
            case .convertContent:
                next.heightMode = .hug
                updates.append(("heightMode", .string("hug")))
                if !node.kind.isLinkControl, CanonicalPageFlow.role(node) == nil {
                    next.widthMode = .fill
                    updates.append(("widthMode", .string("fill")))
                    if CanonicalSizingConstraints.boundsSupportedKinds.contains(node.kind), next.maxWidth == nil {
                        next.maxWidth = frame.size.width
                        updates.append(("maxWidth", .number(frame.size.width)))
                    }
                }
                // Only this explicitly confirmed conversion removes deliberate
                // dimension overrides. Text, links, IDs, ordering and X/Y remain.
                let overriddenKeys = Set(ResponsiveBreakpoint.allCases.flatMap { breakpoint in
                    [ResponsiveGeometryResolver.key(.width, breakpoint: breakpoint),
                     ResponsiveGeometryResolver.key(.height, breakpoint: breakpoint)]
                } + [CanonicalFluidValueCodec.key(.width), CanonicalFluidValueCodec.key(.height)])
                for property in node.properties where overriddenKeys.contains(property.key.rawValue) {
                    changes.append(.removeProperty(.init(pageID: page.id, nodeID: id, propertyID: property.id)))
                }
                driver = .width
            case .setMode(let dimension, let mode):
                if dimension == .width { next.widthMode = mode; driver = .width }
                else { next.heightMode = mode; driver = .height }
                updates.append((dimension.rawValue + "Mode", mode == .fixed ? nil : .string(mode.rawValue)))
            case .set(let field, let value):
                if let value {
                    guard value.isFinite, value >= 0, value <= CanonicalSizingConstraints.maximum else {
                        throw SizingConstraintError.invalid
                    }
                }
                switch field {
                case .minWidth: next.minWidth = value; driver = .width
                case .minHeight: next.minHeight = value; driver = .height
                case .maxWidth: next.maxWidth = value; driver = .width
                case .maxHeight: next.maxHeight = value; driver = .height
                case .aspectRatio:
                    if let value {
                        guard (CanonicalSizingConstraints.minimumRatio...CanonicalSizingConstraints.maximumRatio).contains(value) else {
                            throw SizingConstraintError.invalid
                        }
                        next.aspectRatio = value; next.aspectEnabled = true
                        updates.append(("aspectEnabled", .boolean(true)))
                    } else {
                        next.aspectRatio = nil; next.aspectEnabled = false
                        updates.append(("aspectEnabled", nil))
                    }
                    driver = .width
                }
                updates.append((field.rawValue, value.map(PropertyValue.number)))
            case .setAspectEnabled(let enabled):
                next.aspectEnabled = enabled
                if enabled {
                    let ratio = frame.size.width / frame.size.height
                    guard ratio.isFinite,
                          (CanonicalSizingConstraints.minimumRatio...CanonicalSizingConstraints.maximumRatio).contains(ratio) else {
                        throw SizingConstraintError.invalid
                    }
                    next.aspectRatio = ratio
                    updates.append(("aspectRatio", .number(ratio)))
                }
                updates.append(("aspectEnabled", .boolean(enabled)))
                driver = .width
            case .reset:
                next = .unconstrained
                updates = ["minWidth", "minHeight", "maxWidth", "maxHeight", "aspectRatio", "aspectEnabled", "widthMode", "heightMode"].map { ($0, nil) }
                driver = .width
            }
            guard next.isValid else { throw SizingConstraintError.invalid }
            let adjusted = try SizingConstraintPolicy.adjusted(width: frame.size.width,
                height: frame.size.height, constraints: next, driver: driver)
            for (suffix, value) in updates {
                let key = CanonicalSizingConstraints.prefix + suffix
                let old = node.insertionProperty(key)
                if let value {
                    if old?.value == value, old?.origin == .authored { continue }
                    changes.append(.setProperty(.init(pageID: page.id, nodeID: id,
                        property: .init(id: old?.id ?? PropertyID(), key: .init(rawValue: key),
                            value: value, origin: .authored))))
                } else if let old {
                    changes.append(.removeProperty(.init(pageID: page.id, nodeID: id, propertyID: old.id)))
                }
            }
            for (key, value) in [("layout.width", adjusted.width), ("layout.height", adjusted.height)] {
                if key == "layout.width", next.widthMode != .fixed { continue }
                if key == "layout.height", next.heightMode != .fixed { continue }
                guard let old = node.insertionProperty(key), old.value != .number(value) else { continue }
                changes.append(.setProperty(.init(pageID: page.id, nodeID: id,
                    property: .init(id: old.id, key: old.key, value: .number(value), origin: .authored))))
            }
        }
        guard !applicable.isEmpty else { throw SizingConstraintError.unavailable }
        guard !changes.isEmpty else { throw SizingConstraintError.unchanged }
        let documentCommand = DocumentCommand.batch(changes)
        guard CommandRegistry().availability(for: documentCommand, in: document).isEnabled else {
            throw SizingConstraintError.invalid
        }
        return .init(documentCommand: documentCommand, applicableNodeIDs: applicable, skippedNodeIDs: skipped)
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
        let transformNodesByID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let automaticSizing = page.hasAutomaticSizing
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
            guard !CanonicalPageFlow.isManaged(node), !CanonicalPageChrome.ownsFrame(of: node, in: page) else {
                throw TransformError.incompatibleGeometry
            }
            guard !automaticSizing || !GeometryInspectorField.allCases.contains(where: {
                CanonicalSizingConstraints.isLayoutResolved($0, node: node, page: page,
                    breakpoint: .desktop, width: nil, nodesByID: transformNodesByID)
            }) else { throw TransformError.incompatibleGeometry }
            let sizing: CanonicalSizingConstraints? = [.frame, .image].contains(node.kind)
                ? CanonicalSizingConstraints.resolved(for: node) : nil
            let preview = try Self.resolve(original, operation: command.operation, sizing: sizing)
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

    static func resolve(_ frame: WorldRect, operation: TransformOperation,
                        sizing: CanonicalSizingConstraints? = nil) throws -> WorldRect {
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
            if let sizing {
                let horizontal = [.left, .right].contains(handle)
                let vertical = [.top, .bottom].contains(handle)
                let driver: SizingConstraintPolicy.Driver = horizontal ? .width : vertical ? .height
                    : abs(delta.dx / frame.size.width) >= abs(delta.dy / frame.size.height) ? .width : .height
                let adjusted: (width: Double, height: Double)
                do {
                    adjusted = try SizingConstraintPolicy.adjusted(width: width, height: height,
                        constraints: sizing, driver: driver)
                } catch { throw TransformError.invalidResult }
                width = adjusted.width; height = adjusted.height
                if [.topLeft, .left, .bottomLeft].contains(handle) { x = frame.origin.x + frame.size.width - width }
                if [.topLeft, .top, .topRight].contains(handle) { y = frame.origin.y + frame.size.height - height }
            }
            return try validated(WorldRect(origin: WorldPoint(x: x, y: y),
                size: WorldSize(width: width, height: height)))
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

enum FluidValueProvenance: String, Sendable {
    case pointer, keyboard, focusLoss = "focus-loss", accessibility, automation
}

enum FluidValueInspectorValue: Equatable, Sendable {
    case single(CanonicalFluidValue, PropertyOrigin, applicableCount: Int, skippedCount: Int)
    case mixed(applicableCount: Int, skippedCount: Int)
    case unavailable(String)
}

struct FluidValueCommand: Sendable {
    let identity: GeometryInspectorOperationIdentity
    let orderedNodeIDs: [NodeID]
    let target: FluidValueTarget
    let value: CanonicalFluidValue?
    let provenance: FluidValueProvenance
    let cancelled: Bool
}

struct PreparedFluidValueEdit: Sendable {
    let identity: GeometryInspectorOperationIdentity
    let target: FluidValueTarget
    let applicableNodeIDs: [NodeID]
    let skippedNodeIDs: [NodeID]
    let documentCommand: DocumentCommand
}

enum FluidValueCommandError: Error, Equatable, LocalizedError, Sendable {
    case stale, cancelled, duplicateTarget, emptySelection, missingTarget
    case lockedTarget, hiddenTarget, unavailableTarget, invalidValue
    case noApplicableTargets, noChanges, revisionExhausted, lifecycleUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .stale: "The fluid-value edit is stale; committed content is unchanged."
        case .cancelled: "The fluid-value draft was cancelled; committed content is unchanged."
        case .duplicateTarget: "The fluid-value selection contains a duplicate object."
        case .emptySelection: "Select an object that supports fluid sizing or spacing."
        case .missingTarget: "A selected object is no longer on the active page."
        case .lockedTarget: "Unlock the selected object before editing fluid values."
        case .hiddenTarget: "Show the selected object before editing fluid values."
        case .unavailableTarget: "A selected object is unavailable in the current scene."
        case .invalidValue: "Use finite monotonic minimum, preferred, and maximum values in the supported range."
        case .noApplicableTargets: "The selection has no object that supports this fluid value."
        case .noChanges: "The selected objects already use that fluid value."
        case .revisionExhausted: "The document cannot accept another fluid-value revision."
        case .lifecycleUnavailable(let reason): reason
        }
    }
}

struct FluidValueCommandRegistry: Sendable {
    static let requirementIDs = Set((1...8).map { String(format: "SF-0604-%03d", $0) })

    static func effectiveValue(for target: FluidValueTarget, node: DocumentNode,
                               breakpoint: ResponsiveBreakpoint, viewportWidth: Double)
        -> (Double, ResponsiveGeometrySource)? {
        guard target.supports(node.kind), viewportWidth.isFinite, viewportWidth > 0 else { return nil }
        switch target {
        case .width, .height:
            return ResponsiveGeometryResolver.value(for: target == .width ? .width : .height,
                node: node, breakpoint: breakpoint, viewportWidth: viewportWidth).map { ($0.0, $0.2) }
        case .padding, .gap:
            guard let value = ResponsiveContainerLayoutResolver.value(
                for: target == .padding ? .padding : .gap, node: node,
                breakpoint: breakpoint, viewportWidth: viewportWidth),
                case .number(let number) = value.0 else { return nil }
            return (number, value.2)
        case .fontSize, .lineHeight:
            guard let typography = TypographyCommandRegistry.resolvedTypography(for: node, viewportWidth: viewportWidth) else { return nil }
            return (target == .fontSize ? typography.size : typography.lineHeight,
                    CanonicalFluidValueCodec.value(for: target, node: node) == nil ? .baseDesktop : .fluid)
        }
    }

    func value(for target: FluidValueTarget, in document: CanonicalDocument,
               context: TransformValidationContext) -> FluidValueInspectorValue {
        guard let page = document.pages.first(where: { $0.id == context.activePageID }) else {
            return .unavailable("The active page is unavailable.")
        }
        let selected = context.selectedNodeIDs.compactMap { id in page.nodes.first { $0.id == id } }
        let applicable = selected.filter { target.supports($0.kind) }
        guard !applicable.isEmpty else {
            return .unavailable("The selection does not support fluid \(target.title.lowercased()).")
        }
        let values = applicable.map { CanonicalFluidValueCodec.value(for: target, node: $0) }
        guard let first = values.first else { return .unavailable("Fluid value unavailable.") }
        if values.dropFirst().allSatisfy({ Self.samePresentedRange($0, first) }) {
            if let first {
                return .single(first.0, first.1, applicableCount: applicable.count,
                               skippedCount: selected.count - applicable.count)
            }
            return .unavailable("Fluid \(target.title.lowercased()) is off; the fixed authored value remains active.")
        }
        return .mixed(applicableCount: applicable.count, skippedCount: selected.count - applicable.count)
    }

    // Separate per-object identities do not make otherwise identical ranges
    // visually Mixed. Commits still preserve every object's own FluidValueID.
    private static func samePresentedRange(
        _ lhs: (CanonicalFluidValue, PropertyOrigin)?, _ rhs: (CanonicalFluidValue, PropertyOrigin)?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case (.some(let lhs), .some(let rhs)):
            lhs.1 == rhs.1 && lhs.0.minimum == rhs.0.minimum
                && lhs.0.preferred == rhs.0.preferred && lhs.0.maximum == rhs.0.maximum
                && lhs.0.curve == rhs.0.curve
        default: false
        }
    }

    func prepare(_ command: FluidValueCommand, in document: CanonicalDocument,
                 context: TransformValidationContext) throws -> PreparedFluidValueEdit {
        guard !command.cancelled else { throw FluidValueCommandError.cancelled }
        guard context.isLifecycleAvailable else {
            throw FluidValueCommandError.lifecycleUnavailable(
                context.lifecycleDisabledReason ?? "Fluid editing is unavailable during the current document operation.")
        }
        guard command.identity.documentID == document.id,
              command.identity.pageID == context.activePageID,
              command.identity.revision == document.revision,
              command.identity.sceneID == context.currentSceneID,
              command.identity.rendererGeneration == context.rendererGeneration,
              command.orderedNodeIDs == context.selectedNodeIDs,
              let page = document.pages.first(where: { $0.id == context.activePageID }) else {
            throw FluidValueCommandError.stale
        }
        guard document.revision < UInt64.max else { throw FluidValueCommandError.revisionExhausted }
        guard !command.orderedNodeIDs.isEmpty else { throw FluidValueCommandError.emptySelection }
        guard Set(command.orderedNodeIDs).count == command.orderedNodeIDs.count else {
            throw FluidValueCommandError.duplicateTarget
        }
        if let value = command.value {
            guard value.isValid,
                  command.target.accepts(value.minimum), command.target.accepts(value.preferred),
                  command.target.accepts(value.maximum) else { throw FluidValueCommandError.invalidValue }
        }

        var applicable: [NodeID] = [], skipped: [NodeID] = [], changes: [DocumentCommand] = []
        var assignedValueIDs = Set(document.pages.flatMap(\.nodes).flatMap { node in
            FluidValueTarget.allCases.compactMap {
                CanonicalFluidValueCodec.value(for: $0, node: node)?.0.id
            }
        })
        for id in command.orderedNodeIDs {
            guard let node = page.nodes.first(where: { $0.id == id }),
                  let current = CanonicalFluidValueCodec.value(for: command.target, node: node)?.0 else { continue }
            assignedValueIDs.remove(current.id)
        }
        for id in command.orderedNodeIDs {
            guard let node = page.nodes.first(where: { $0.id == id }) else {
                throw FluidValueCommandError.missingTarget
            }
            guard command.target.supports(node.kind) else { skipped.append(id); continue }
            if [.width, .height].contains(command.target), CanonicalPageChrome.ownsFrame(of: node, in: page) {
                skipped.append(id); continue
            }
            guard !node.insertionBooleanProperty("locked") else { throw FluidValueCommandError.lockedTarget }
            guard !node.insertionBooleanProperty("hidden") else { throw FluidValueCommandError.hiddenTarget }
            guard context.availableNodeIDs.contains(id) else { throw FluidValueCommandError.unavailableTarget }
            let key = CanonicalFluidValueCodec.key(command.target)
            let existing = node.insertionProperty(key)
            if let value = command.value {
                if command.target == .fontSize || command.target == .lineHeight {
                    guard Self.typographyRemainsValid(node: node, replacing: command.target, with: value) else {
                        throw FluidValueCommandError.invalidValue
                    }
                }
                let existingValue: CanonicalFluidValue? = existing.flatMap {
                    guard case .string(let raw) = $0.value else { return nil }
                    return try? CanonicalFluidValueCodec.decode(raw, target: command.target)
                }
                let identity: FluidValueID
                if let existingValue {
                    guard assignedValueIDs.insert(existingValue.id).inserted else {
                        throw FluidValueCommandError.invalidValue
                    }
                    identity = existingValue.id
                } else if assignedValueIDs.insert(value.id).inserted {
                    identity = value.id
                } else {
                    var generated = FluidValueID()
                    while !assignedValueIDs.insert(generated).inserted { generated = FluidValueID() }
                    identity = generated
                }
                let canonicalValue = CanonicalFluidValue(
                    id: identity, minimum: value.minimum, preferred: value.preferred,
                    maximum: value.maximum, curve: value.curve)
                let encoded: String
                do { encoded = try CanonicalFluidValueCodec.encode(canonicalValue, target: command.target) }
                catch { throw FluidValueCommandError.invalidValue }
                if existing?.value == .string(encoded), existing?.origin == .authored { continue }
                applicable.append(id)
                changes.append(.setProperty(.init(pageID: page.id, nodeID: id,
                    property: .init(id: existing?.id ?? PropertyID(), key: .init(rawValue: key),
                                    value: .string(encoded), origin: .authored),
                    insertionIndex: existing == nil ? node.properties.count : nil)))
            } else if let existing {
                applicable.append(id)
                changes.append(.removeProperty(.init(pageID: page.id, nodeID: id, propertyID: existing.id)))
            }
        }
        guard !applicable.isEmpty else {
            if skipped.count == command.orderedNodeIDs.count { throw FluidValueCommandError.noApplicableTargets }
            throw FluidValueCommandError.noChanges
        }
        let documentCommand = DocumentCommand.batch(changes)
        guard CommandRegistry().availability(for: documentCommand, in: document).isEnabled else {
            throw FluidValueCommandError.invalidValue
        }
        return .init(identity: command.identity, target: command.target,
                     applicableNodeIDs: applicable, skippedNodeIDs: skipped,
                     documentCommand: documentCommand)
    }

    private static func typographyRemainsValid(
        node: DocumentNode, replacing target: FluidValueTarget, with value: CanonicalFluidValue
    ) -> Bool {
        guard let fixed = CanonicalTypography.resolved(for: node) else { return false }
        return [CanonicalFluidValue.lowerViewport, CanonicalFluidValue.preferredViewport,
                CanonicalFluidValue.upperViewport].allSatisfy { width in
            let size = target == .fontSize
                ? value.resolved(viewportWidth: width)
                : CanonicalFluidValueCodec.resolved(.fontSize, node: node, viewportWidth: width) ?? fixed.size
            let lineHeight = target == .lineHeight
                ? value.resolved(viewportWidth: width)
                : CanonicalFluidValueCodec.resolved(.lineHeight, node: node, viewportWidth: width) ?? fixed.lineHeight
            guard let size, let lineHeight else { return false }
            return CanonicalTypography(
                family: fixed.family, weight: fixed.weight, size: size, lineHeight: lineHeight,
                tracking: fixed.tracking, alignment: fixed.alignment).isValid
        }
    }
}

enum FluidValueDiagnosticResult: String, Codable, Sendable { case success, failure, cancelled, stale }

struct FluidValueDiagnosticRecord: Codable, Equatable, Sendable {
    let requirementIDs: [String]
    let operationType: String
    let provenance: String
    let sanitizedIdentifiers: [String]
    let durationMilliseconds: Double
    let parentRevision: UInt64
    let resultRevision: UInt64?
    let result: FluidValueDiagnosticResult
    let failureCategory: String?
}

actor FluidValueDiagnostics {
    private var buffer = BoundedDiagnosticBuffer<FluidValueDiagnosticRecord>(
        capacity: DiagnosticRetentionPolicy.defaultCapacity)
    func append(_ record: FluidValueDiagnosticRecord) { buffer.append(record) }
    func snapshot() -> [FluidValueDiagnosticRecord] { buffer.snapshot() }
}

enum FluidValueDiagnosticFactory {
    static func make(command: FluidValueCommand, durationMilliseconds: Double,
                     resultRevision: UInt64?, result: FluidValueDiagnosticResult,
                     failure: FluidValueCommandError?) -> FluidValueDiagnosticRecord {
        .init(requirementIDs: FluidValueCommandRegistry.requirementIDs.sorted(),
              operationType: command.value == nil ? "fluid-value.remove" : "fluid-value.set",
              provenance: command.provenance.rawValue,
              sanitizedIdentifiers: command.orderedNodeIDs.map {
                  DiagnosticStableIdentifier.sanitize($0.description, domain: .fluidValue, kind: "node")
              }, durationMilliseconds: max(0, durationMilliseconds),
              parentRevision: command.identity.revision, resultRevision: resultRevision,
              result: result, failureCategory: failure.map(Self.category))
    }

    private static func category(_ error: FluidValueCommandError) -> String {
        switch error {
        case .stale: "stale-identity"
        case .cancelled: "cancelled"
        case .duplicateTarget, .emptySelection, .missingTarget: "invalid-target"
        case .lockedTarget, .hiddenTarget, .unavailableTarget: "unavailable-target"
        case .invalidValue: "invalid-value"
        case .noApplicableTargets: "no-applicable-target"
        case .noChanges: "no-change"
        case .revisionExhausted: "revision-exhausted"
        case .lifecycleUnavailable: "lifecycle-unavailable"
        }
    }
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
    case fluidValueWins
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
        case .fluidValueWins:
            "A fluid value controls Desktop spacing. Edit or remove it in Fluid Value before changing fixed spacing. Tablet and Mobile overrides remain available."
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
        breakpoint: ResponsiveBreakpoint = .desktop,
        viewportWidth: Double? = nil
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
            ResponsiveContainerLayoutResolver.value(for: field, node: node, breakpoint: breakpoint,
                                                   viewportWidth: viewportWidth)
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
                // Do not accept a fixed edit which the shared fluid resolver
                // will ignore. Removing fluid intent is a separate, undoable
                // command, not an implicit side effect of editing this field.
                let fluidTarget: FluidValueTarget? = switch command.field {
                case .padding: .padding
                case .gap: .gap
                default: nil
                }
                if let fluidTarget, CanonicalFluidValueCodec.value(for: fluidTarget, node: node) != nil {
                    throw ContainerLayoutError.fluidValueWins
                }
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
        case .fluidValueWins: "fluid-value-wins"
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

// MARK: - Image inspector command boundary

enum ImageFillEdit: Sendable {
    case setAsset(AssetID)
    case setMode(ImageFitMode)
    case remove
}

enum ImageFillCommandError: Error, LocalizedError, Equatable, Sendable {
    case stale, cancelled, unavailable, invalidAsset, noApplicableTargets, noChanges
    var errorDescription: String? {
        switch self {
        case .stale: "The document, selection, or renderer changed. Review the image fill and try again."
        case .cancelled: "Image fill edit cancelled; the document is unchanged."
        case .unavailable: "Unlock and show the selected object before editing its image fill."
        case .invalidAsset: "Choose a compatible imported local image asset."
        case .noApplicableTargets: "Select a Frame or Section to edit its image fill."
        case .noChanges: "The image fill already has that value."
        }
    }
}

/// An Assets-pane edit is prepared against the same live document and scene
/// selection that will execute it. DocumentSession supplies the exact inverse.
struct AssetOrganizationEditIdentity: Equatable, Sendable {
    let documentID: DocumentID
    let revision: UInt64
    let assetID: AssetID
    let sceneID: CanvasViewportSceneID
}

enum AssetOrganizationEditError: Error, Equatable {
    case cancelled, stale, invalid, noChanges

    var message: String {
        switch self {
        case .cancelled: "Asset organization edit cancelled; the project is unchanged."
        case .stale: "The asset or document changed. Select the asset and try again."
        case .invalid: "Use a folder of up to four names and up to twelve distinct short tags."
        case .noChanges: "Asset organization is already up to date."
        }
    }
}

struct AssetOrganizationCommandRegistry: Sendable {
    func prepare(folder: String?, tags: [String], favorite: Bool,
                 identity: AssetOrganizationEditIdentity, live: AssetOrganizationEditIdentity,
                 document: CanonicalDocument, cancelled: Bool = false) throws -> DocumentCommand {
        if cancelled { throw AssetOrganizationEditError.cancelled }
        guard identity == live, identity.documentID == document.id,
              identity.revision == document.revision,
              document.revision < UInt64.max - 1,
              var asset = document.imageAssets.first(where: { $0.id == identity.assetID }) else {
            throw AssetOrganizationEditError.stale
        }
        let organization: AssetOrganization
        do { organization = try AssetOrganization(folderPath: folder, tags: tags, favorite: favorite) }
        catch { throw AssetOrganizationEditError.invalid }
        let replacement = organization.isEmpty ? nil : organization
        guard asset.organization != replacement else { throw AssetOrganizationEditError.noChanges }
        asset.organization = replacement
        return .updateImageAsset(.init(asset: asset))
    }
}

struct ImageFillCommandRegistry: Sendable {
    func prepare(_ edit: ImageFillEdit, identity: ImageInspectorOperationIdentity,
                 in document: CanonicalDocument, context: TransformValidationContext,
                 cancelled: Bool = false) throws -> PreparedImageInspectorEdit {
        if cancelled { throw ImageFillCommandError.cancelled }
        guard identity.documentID == document.id, identity.revision == document.revision,
              identity.sceneID == context.currentSceneID,
              identity.rendererGeneration == context.rendererGeneration,
              identity.pageID == context.activePageID,
              identity.selectedNodeIDs == context.selectedNodeIDs,
              !identity.selectedNodeIDs.isEmpty,
              Set(identity.selectedNodeIDs).count == identity.selectedNodeIDs.count,
              document.revision < UInt64.max - 1,
              let page = document.pages.first(where: { $0.id == identity.pageID }) else {
            throw ImageFillCommandError.stale
        }
        guard context.isLifecycleAvailable else { throw ImageFillCommandError.unavailable }
        if case .setAsset(let id) = edit {
            guard document.imageAssets.contains(where: { $0.id == id }) else { throw ImageFillCommandError.invalidAsset }
        }
        var applicable: [NodeID] = [], skipped: [NodeID] = [], changes: [DocumentCommand] = []
        for id in identity.selectedNodeIDs {
            guard let node = page.nodes.first(where: { $0.id == id }) else { throw ImageFillCommandError.stale }
            guard [.frame, .section].contains(node.kind) else { skipped.append(id); continue }
            guard context.availableNodeIDs.contains(id), !node.selectionBooleanProperty("locked"),
                  !node.selectionBooleanProperty("hidden") else { throw ImageFillCommandError.unavailable }
            applicable.append(id)
            let replacements: [(String, PropertyValue)]
            let owned: [String]
            switch edit {
            case .setAsset(let asset):
                replacements = [(CanonicalImageFill.assetKey, .string(asset.description))]
                owned = [CanonicalImageFill.assetKey]
            case .setMode(let mode):
                guard CanonicalImageFill.resolve(node) != nil, mode == .fit || mode == .fill else {
                    throw ImageFillCommandError.invalidAsset
                }
                replacements = [(CanonicalImageFill.modeKey, .string(mode.rawValue))]
                owned = [CanonicalImageFill.modeKey]
            case .remove:
                replacements = []
                owned = [CanonicalImageFill.assetKey, CanonicalImageFill.modeKey]
            }
            for key in owned {
                let old = node.insertionProperty(key)
                if let value = replacements.first(where: { $0.0 == key })?.1 {
                    if old?.value != value || old?.origin != .authored {
                        changes.append(.setProperty(.init(pageID: page.id, nodeID: id,
                            property: .init(id: old?.id ?? PropertyID(), key: .init(rawValue: key),
                                            value: value, origin: .authored))))
                    }
                } else if let old {
                    changes.append(.removeProperty(.init(pageID: page.id, nodeID: id, propertyID: old.id)))
                }
            }
        }
        guard !applicable.isEmpty else { throw ImageFillCommandError.noApplicableTargets }
        guard !changes.isEmpty else { throw ImageFillCommandError.noChanges }
        let command: DocumentCommand = changes.count == 1 ? changes[0] : .batch(changes)
        guard CommandRegistry().availability(for: command, in: document).isEnabled else { throw ImageFillCommandError.stale }
        return .init(command: command, applicableNodeIDs: applicable, skippedNodeIDs: skipped)
    }
}

enum ImageInspectorPresentation: Equatable, Sendable {
    case single(CanonicalImageStyle, ImageAsset)
    case mixed(applicable: Int, skipped: Int)
    case unavailable(String)
}

/// Per-property presentation never borrows the primary Image's value when
/// different assets happen to share fit/semantics. No resource bytes are read.
struct ImageInspectorSelection: Equatable, Sendable {
    let applicableCount: Int
    let skippedCount: Int
    let assetID: AssetID?
    let fit: ImageFitMode?
    let focalX: Double?
    let focalY: Double?
    let altText: String?
    let decorative: Bool?

    init?(nodes: [DocumentNode]) {
        let images = nodes.filter { $0.kind == .image }
        let styles = images.compactMap(CanonicalImageStyle.resolve)
        guard !images.isEmpty, images.count == styles.count else { return nil }
        func common<T: Equatable>(_ values: [T]) -> T? {
            guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
            return first
        }
        applicableCount = images.count; skippedCount = nodes.count - images.count
        assetID = common(styles.map(\.assetID)); fit = common(styles.map(\.fitMode))
        focalX = common(styles.map(\.focalX)); focalY = common(styles.map(\.focalY))
        altText = common(styles.map(\.altText)); decorative = common(styles.map(\.isDecorative))
    }

    /// Untouched coordinates use their exact common canonical value, not the
    /// rounded percentage displayed in the text field. A mixed coordinate
    /// requires an explicit draft; it cannot borrow from the primary image.
    func detailsEdit(focalXDraft: String?, focalYDraft: String?, altDraft: String?) throws -> ImageInspectorEdit {
        var x: Double?, y: Double?
        if focalXDraft != nil || focalYDraft != nil {
            x = focalXDraft.flatMap { Double($0) }.map { $0 / 100 } ?? (focalXDraft == nil ? focalX : nil)
            y = focalYDraft.flatMap { Double($0) }.map { $0 / 100 } ?? (focalYDraft == nil ? focalY : nil)
            guard let x, let y, x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else {
                throw ImageInspectorError.invalidFocalPoint
            }
        }
        return .details(focalX: x, focalY: y, altText: altDraft)
    }
}

enum ImageInspectorDraftField: Hashable, Sendable { case focalX, focalY, alt }

struct ImageInspectorDraft: Equatable, Sendable {
    var text: String
    let openingText: String
    let context: ResponsiveInspectorEditContext
    var isUnchanged: Bool { text == openingText }
    func canCommit(in current: ResponsiveInspectorEditContext) -> Bool { context == current }
}

enum ImageInspectorEdit: Equatable, Sendable {
    case asset(AssetID)
    case fit(ImageFitMode)
    case focal(x: Double, y: Double)
    case altText(String)
    case decorative(Bool)
    case details(focalX: Double?, focalY: Double?, altText: String?)
}

struct ImageInspectorOperationIdentity: Equatable, Sendable {
    let documentID: DocumentID
    let pageID: PageID
    let revision: UInt64
    let sceneID: CanvasViewportSceneID
    let rendererGeneration: UInt64
    let selectedNodeIDs: [NodeID]
}

struct ImageInspectorCommand: Equatable, Sendable {
    let identity: ImageInspectorOperationIdentity
    let edit: ImageInspectorEdit
}

struct ImageAssetUseRequest: Identifiable, Equatable, Sendable {
    enum Target: Equatable, Sendable {
        case image, fill
        case componentMedia(instanceID: NodeID, propertyID: ComponentMediaPropertyID)
    }
    let id = UUID()
    let identity: ImageInspectorOperationIdentity
    let target: Target
    let definitionEditing: Bool
    init(identity: ImageInspectorOperationIdentity, target: Target, definitionEditing: Bool = false) {
        self.identity = identity; self.target = target; self.definitionEditing = definitionEditing
    }
    var scopeDescription: String {
        if case .componentMedia = target { return "Only this instance's exposed image override changes. The definition and other instances keep their image." }
        if definitionEditing { return "This definition changes inherited images in linked instances. Authored instance media overrides stay independent." }
        return "Only selected uses change. Other objects keep the existing asset; fit, alt text and authored geometry are preserved."
    }
}

extension ImageInspectorCommandRegistry {
    /// All use scopes delegate to their existing typed registry. Imported
    /// metadata is staged only in a candidate so new asset + reference form
    /// one real transaction, with resources installed by the lifecycle owner.
    func prepareAssetUse(_ assetID: AssetID, request: ImageAssetUseRequest, in document: CanonicalDocument,
                         context: TransformValidationContext, cancelled: Bool = false) throws -> DocumentCommand {
        guard !cancelled else { throw ImageInspectorError.cancelled }
        guard context.isLifecycleAvailable else { throw ImageInspectorError.unavailableTarget }
        switch request.target {
        case .image:
            let prepared = try prepare(.init(identity: request.identity, edit: .asset(assetID)), in: document, context: context, cancelled: cancelled)
            let nodes = document.pages.first { $0.id == request.identity.pageID }?.nodes ?? []
            if prepared.applicableNodeIDs.allSatisfy({ id in nodes.first { $0.id == id }?.insertionStringProperty(CanonicalImageStyle.namespace + "assetID") == assetID.description }) { return .batch([]) }
            return prepared.command
        case .fill:
            return try ImageFillCommandRegistry().prepare(.setAsset(assetID), identity: request.identity, in: document, context: context, cancelled: cancelled).command
        case .componentMedia(let instanceID, let propertyID):
            let identity = request.identity
            guard identity.selectedNodeIDs == context.selectedNodeIDs else { throw ImageInspectorError.selectionMismatch }
            return try ComponentCommandRegistry().prepare(.setMediaOverride(instanceID: instanceID, propertyID: propertyID, assetID: assetID),
                identity: .init(documentID: identity.documentID, pageID: identity.pageID, revision: identity.revision,
                    sceneID: identity.sceneID, rendererGeneration: identity.rendererGeneration), in: document, context: context, cancelled: cancelled).command
        }
    }

    func prepareImportedAssetUse(_ imported: PreparedImageImport?, request: ImageAssetUseRequest,
                                in document: CanonicalDocument, context: TransformValidationContext) throws
        -> (command: DocumentCommand, assetID: AssetID, installsResource: Bool) {
        guard let imported else { throw ImageImportError.cancelled }
        let existing = document.imageAssets.first { $0.contentHash == imported.asset.contentHash }
        let assetID = existing?.id ?? imported.asset.id
        var candidate = document
        if existing == nil { candidate.imageAssets.append(imported.asset) }
        let use = try prepareAssetUse(assetID, request: request, in: candidate, context: context)
        let command: DocumentCommand = existing == nil
            ? .batch([.insertImageAsset(.init(asset: imported.asset, index: document.imageAssets.count)), use]) : use
        if case .batch(let commands) = command, commands.isEmpty { return (command, assetID, false) }
        guard CommandRegistry().availability(for: command, in: document).isEnabled else { throw ImageInspectorError.invalidAsset }
        return (command, assetID, existing == nil)
    }
}

struct PreparedImageInspectorEdit: Equatable, Sendable {
    let command: DocumentCommand
    let applicableNodeIDs: [NodeID]
    let skippedNodeIDs: [NodeID]
}

enum ImageInspectorError: Error, Equatable, LocalizedError, Sendable {
    case cancelled, emptySelection, staleDocument, staleRevision, staleRenderer,
         pageUnavailable, selectionMismatch, duplicateTarget, missingTarget,
         lockedTarget, hiddenTarget, unavailableTarget, noApplicableTarget,
         invalidAsset, invalidFocalPoint, invalidAltText, revisionExhausted

    var errorDescription: String? {
        switch self {
        case .cancelled: "Image edit cancelled; the committed value is unchanged."
        case .emptySelection: "Select an Image to edit its image properties."
        case .staleDocument, .staleRevision, .staleRenderer: "The canvas changed before this Image edit committed. Try again."
        case .pageUnavailable: "The Image page is no longer active."
        case .selectionMismatch: "The Image selection changed before this edit committed."
        case .duplicateTarget: "The Image selection contains a duplicate stable identity."
        case .missingTarget: "A selected Image no longer exists."
        case .lockedTarget: "Unlock the selected Image before editing it."
        case .hiddenTarget: "Show the selected Image before editing it."
        case .unavailableTarget: "The selected Image is not available in the adopted renderer."
        case .noApplicableTarget: "This selection contains no editable Image nodes."
        case .invalidAsset: "Choose an imported image asset."
        case .invalidFocalPoint: "Focal point values must be between 0 and 100 percent."
        case .invalidAltText: "Alternative text must be valid plain text no longer than 4,096 UTF-8 bytes."
        case .revisionExhausted: "The document revision cannot accept another Image edit."
        }
    }
}

// MARK: - Form field inspector command boundary

/// The Inspector owns only this typed edit intent. Canonical metadata remains
/// the existing `form.field.v1.*` property namespace on a Text child of Form.
enum FormFieldKind: String, CaseIterable, Sendable {
    case text, email, textarea, checkbox, select, submit

    var title: String { rawValue == "textarea" ? "Text Area" : rawValue.capitalized }
}

struct FormFieldConfiguration: Equatable, Sendable {
    let kind: FormFieldKind
    let label: String
    let name: String
    let help: String?
    let required: Bool
    let options: [CanonicalFormSelectOption]
    let maximumLength: Int?

    init(kind: FormFieldKind, label: String, name: String, help: String?, required: Bool,
         options: [CanonicalFormSelectOption], maximumLength: Int? = nil) {
        self.kind = kind; self.label = label; self.name = name; self.help = help
        self.required = required; self.options = options; self.maximumLength = maximumLength
    }
}

enum FormInspectorAggregateValue: Equatable, Sendable {
    case value(String, provenance: String)
    case mixed
    case unavailable(String)

    var displayValue: String {
        switch self {
        case .value(let value, _): value
        case .mixed: "Mixed"
        case .unavailable(let reason): reason
        }
    }

    var provenance: String {
        switch self {
        case .value(_, let provenance): provenance
        case .mixed: "Mixed provenance"
        case .unavailable: "Unavailable"
        }
    }
}

/// A read-only projection of canonical field metadata for Content and
/// Accessibility inspectors. It deliberately carries no draft state and
/// cannot compile a command, preventing accessibility presentation from
/// becoming a second source of truth.
struct FormFieldInspectorPresentation: Equatable, Sendable {
    let applicableCount: Int
    let skippedCount: Int
    let kind: FormInspectorAggregateValue
    let accessibleName: FormInspectorAggregateValue
    let machineName: FormInspectorAggregateValue
    let help: FormInspectorAggregateValue
    let required: FormInspectorAggregateValue
    let options: FormInspectorAggregateValue
    let maximumLength: FormInspectorAggregateValue
    let configurationStatus: String

    static func resolve(fields: [DocumentNode], totalSelectionCount: Int) -> Self {
        guard !fields.isEmpty else {
            let unavailable = FormInspectorAggregateValue.unavailable("Select a Form field")
            return .init(applicableCount: 0, skippedCount: totalSelectionCount,
                         kind: unavailable, accessibleName: unavailable, machineName: unavailable,
                         help: unavailable, required: unavailable, options: unavailable,
                         maximumLength: unavailable,
                         configurationStatus: "No Form field is selected.")
        }
        func aggregate(_ values: [(String, PropertyOrigin?)], fallback: String? = nil) -> FormInspectorAggregateValue {
            let resolved = values.map { value, origin in
                (value, origin.map { $0 == .authored ? "Authored" : "Defaulted" } ?? (fallback ?? "Computed fallback"))
            }
            guard let first = resolved.first else { return .unavailable("Unavailable") }
            guard resolved.dropFirst().allSatisfy({ $0.0 == first.0 }) else { return .mixed }
            let provenance = resolved.dropFirst().allSatisfy({ $0.1 == first.1 })
                ? first.1 : "Mixed provenance"
            return .value(first.0, provenance: provenance)
        }
        let kinds = fields.map { node -> (String, PropertyOrigin?) in
            let property = node.insertionProperty(CanonicalFormField.kindKey)
            let raw = node.insertionStringProperty(CanonicalFormField.kindKey) ?? "text"
            return (FormFieldKind(rawValue: raw)?.title ?? "Invalid field type", property?.origin)
        }
        let labels = fields.map { node -> (String, PropertyOrigin?) in
            let property = node.insertionProperty(CanonicalFormField.labelKey)
            return (node.insertionStringProperty(CanonicalFormField.labelKey) ?? node.name, property?.origin)
        }
        let names = fields.map { node -> (String, PropertyOrigin?) in
            let property = node.insertionProperty(CanonicalFormField.nameKey)
            return (node.insertionStringProperty(CanonicalFormField.nameKey) ?? "Not configured", property?.origin)
        }
        let helps = fields.map { node -> (String, PropertyOrigin?) in
            let property = node.insertionProperty(CanonicalFormField.helpKey)
            return (node.insertionStringProperty(CanonicalFormField.helpKey) ?? "No help text", property?.origin)
        }
        let requiredValues = fields.map { node -> (String, PropertyOrigin?) in
            let property = node.insertionProperty(CanonicalFormField.requiredKey)
            return (node.insertionBooleanProperty(CanonicalFormField.requiredKey) ? "Required" : "Optional", property?.origin)
        }
        let optionValues = fields.map { node -> (String, PropertyOrigin?) in
            let property = node.insertionProperty(CanonicalFormField.optionsKey)
            guard let encoded = node.insertionStringProperty(CanonicalFormField.optionsKey),
                  let options = try? CanonicalFormSelectOptions.decode(encoded) else {
                return ("Not applicable", property?.origin)
            }
            return ("\(options.count) ordered option\(options.count == 1 ? "" : "s")", property?.origin)
        }
        let maximumLengths = fields.map { node -> (String, PropertyOrigin?) in
            let property = node.insertionProperty(CanonicalFormField.maximumLengthKey)
            return (node.insertionNumberProperty(CanonicalFormField.maximumLengthKey).map { String(Int($0)) }
                    ?? "Default limit \(CanonicalFormField.maximumMaximumLength)", property?.origin)
        }
        let configuredCount = fields.filter {
            $0.insertionProperty(CanonicalFormField.kindKey) != nil
                && $0.insertionProperty(CanonicalFormField.labelKey) != nil
                && $0.insertionProperty(CanonicalFormField.nameKey) != nil
                && $0.insertionProperty(CanonicalFormField.requiredKey) != nil
        }.count
        let skipped = max(0, totalSelectionCount - fields.count)
        let status = configuredCount == fields.count
            ? "\(fields.count) configured Form field\(fields.count == 1 ? "" : "s"); \(skipped) incompatible selection\(skipped == 1 ? "" : "s") unchanged."
            : "\(configuredCount) of \(fields.count) Form fields configured; edit missing metadata in Content."
        return .init(applicableCount: fields.count, skippedCount: skipped,
                     kind: aggregate(kinds), accessibleName: aggregate(labels),
                     machineName: aggregate(names), help: aggregate(helps),
                     required: aggregate(requiredValues), options: aggregate(optionValues),
                     maximumLength: aggregate(maximumLengths), configurationStatus: status)
    }
}

struct FormContainerAccessibilityPresentation: Equatable, Sendable {
    let fieldCount: Int
    let configuredCount: Int
    let requiredCount: Int
    let submitCount: Int
    let status: String

    static func resolve(form: DocumentNode, page: DocumentPage) -> Self {
        let nodesByID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let fields = form.childIDs.compactMap { nodesByID[$0] }.filter { $0.kind == .text }
        let configured = fields.filter {
            $0.insertionProperty(CanonicalFormField.kindKey) != nil
                && $0.insertionProperty(CanonicalFormField.labelKey) != nil
                && $0.insertionProperty(CanonicalFormField.nameKey) != nil
                && $0.insertionProperty(CanonicalFormField.requiredKey) != nil
        }
        let required = configured.filter { $0.insertionBooleanProperty(CanonicalFormField.requiredKey) }
        let submits = configured.filter { $0.insertionStringProperty(CanonicalFormField.kindKey) == FormFieldKind.submit.rawValue }
        let status = configured.count == fields.count
            ? "All \(fields.count) Form fields have canonical accessible labels and control types. Submission remains disabled until a destination is approved."
            : "\(fields.count - configured.count) Form field\(fields.count - configured.count == 1 ? " needs" : "s need") accessible label and control metadata in Content."
        return .init(fieldCount: fields.count, configuredCount: configured.count,
                     requiredCount: required.count, submitCount: submits.count, status: status)
    }
}

/// A Form edit is intentionally scoped independently from Image Inspector
/// identity so future Form-only lifecycle diagnostics cannot alias an Image
/// operation while sharing the same document/scene revision contract.
struct FormInspectorOperationIdentity: Equatable, Sendable {
    let documentID: DocumentID
    let pageID: PageID
    let revision: UInt64
    let sceneID: CanvasViewportSceneID
    let rendererGeneration: UInt64
    let selectedNodeIDs: [NodeID]
}

enum FormInspectorEdit: Equatable, Sendable {
    case configure(FormFieldConfiguration)
    case removeConfiguration
}

struct FormInspectorCommand: Equatable, Sendable {
    let identity: FormInspectorOperationIdentity
    let edit: FormInspectorEdit
    let cancelled: Bool
}

struct PreparedFormInspectorEdit: Equatable, Sendable {
    let command: DocumentCommand
    let applicableNodeIDs: [NodeID]
    let skippedNodeIDs: [NodeID]
}

enum FormInspectorError: Error, Equatable, LocalizedError, Sendable {
    case cancelled, stale, emptySelection, duplicateTarget, pageUnavailable,
         selectionMismatch, missingTarget, lockedTarget, hiddenTarget,
         unavailableTarget, noApplicableTarget, invalidConfiguration,
         revisionExhausted, noChanges

    var errorDescription: String? {
        switch self {
        case .cancelled: "Form field draft cancelled; committed metadata is unchanged."
        case .stale, .selectionMismatch: "The document, selection, or canvas changed before this Form edit committed."
        case .emptySelection: "Select a Text child of a Form to configure a field."
        case .duplicateTarget: "A Form field edit cannot contain the same object twice."
        case .pageUnavailable: "The active Form page is unavailable."
        case .missingTarget: "A selected Form field no longer exists."
        case .lockedTarget: "Unlock the selected Form field before editing."
        case .hiddenTarget: "Show the selected Form field before editing."
        case .unavailableTarget: "The selected Form field is unavailable in this scene."
        case .noApplicableTarget: "Select a Text child of a Form to configure a field."
        case .invalidConfiguration: "Enter a valid field label, machine name, and select options."
        case .revisionExhausted: "The document revision cannot accept another Form edit."
        case .noChanges: "The Form field already has that configuration."
        }
    }
}

struct FormInspectorCommandRegistry: Sendable {
    static let requirementIDs: Set<String> = Set((1...8).map { String(format: "SF-1006-%03d", $0) })
    private static let ownedKeys: Set<String> = [
        CanonicalFormField.kindKey, CanonicalFormField.labelKey,
        CanonicalFormField.nameKey, CanonicalFormField.helpKey,
        CanonicalFormField.requiredKey, CanonicalFormField.optionsKey,
        CanonicalFormField.maximumLengthKey,
    ]

    func prepare(_ input: FormInspectorCommand, in document: CanonicalDocument,
                 context: TransformValidationContext) throws -> PreparedFormInspectorEdit {
        guard !input.cancelled else { throw FormInspectorError.cancelled }
        let identity = input.identity
        guard identity.documentID == document.id, identity.revision == document.revision,
              identity.sceneID == context.currentSceneID,
              identity.rendererGeneration == context.rendererGeneration else { throw FormInspectorError.stale }
        guard context.isLifecycleAvailable else { throw FormInspectorError.unavailableTarget }
        guard identity.pageID == context.activePageID,
              let page = document.pages.first(where: { $0.id == identity.pageID }) else {
            throw FormInspectorError.pageUnavailable
        }
        guard !identity.selectedNodeIDs.isEmpty else { throw FormInspectorError.emptySelection }
        guard Set(identity.selectedNodeIDs).count == identity.selectedNodeIDs.count else { throw FormInspectorError.duplicateTarget }
        guard identity.selectedNodeIDs == context.selectedNodeIDs else { throw FormInspectorError.selectionMismatch }
        guard document.revision < UInt64.max - 1 else { throw FormInspectorError.revisionExhausted }
        if case .configure(let configuration) = input.edit { try validate(configuration) }

        let nodesByID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        var commands: [DocumentCommand] = []
        var applicable: [NodeID] = []
        var skipped: [NodeID] = []
        for id in identity.selectedNodeIDs {
            guard let node = nodesByID[id] else { throw FormInspectorError.missingTarget }
            guard node.kind == .text,
                  case .node(let parentID) = node.parent,
                  nodesByID[parentID]?.kind == .form else {
                skipped.append(id); continue
            }
            if node.insertionBooleanProperty("locked") { throw FormInspectorError.lockedTarget }
            if node.insertionBooleanProperty("hidden") { throw FormInspectorError.hiddenTarget }
            guard context.availableNodeIDs.contains(id) else { throw FormInspectorError.unavailableTarget }
            applicable.append(id)

            let desired: [(String, PropertyValue, PropertyOrigin)]
            switch input.edit {
            case .removeConfiguration:
                desired = []
            case .configure(let value):
                var values: [(String, PropertyValue, PropertyOrigin)] = [
                    (CanonicalFormField.kindKey, .string(value.kind.rawValue), .authored),
                    (CanonicalFormField.labelKey, .string(value.label), .authored),
                    (CanonicalFormField.nameKey, .string(value.name), .authored),
                    (CanonicalFormField.requiredKey, .boolean(value.required), .authored),
                ]
                if let help = value.help, !help.isEmpty {
                    values.append((CanonicalFormField.helpKey, .string(help), .authored))
                }
                if value.kind == .select {
                    values.append((CanonicalFormField.optionsKey,
                                   .string(try CanonicalFormSelectOptions.encode(value.options)), .authored))
                }
                if let maximumLength = value.maximumLength {
                    values.append((CanonicalFormField.maximumLengthKey, .number(Double(maximumLength)), .authored))
                }
                desired = values
            }
            let desiredKeys = Set(desired.map(\.0))
            for property in node.properties where Self.ownedKeys.contains(property.key.rawValue) && !desiredKeys.contains(property.key.rawValue) {
                commands.append(.removeProperty(.init(pageID: page.id, nodeID: id, propertyID: property.id)))
            }
            for (key, value, origin) in desired {
                let prior = node.insertionProperty(key)
                guard prior?.value != value || prior?.origin != origin else { continue }
                commands.append(.setProperty(.init(pageID: page.id, nodeID: id,
                    property: .init(id: prior?.id ?? PropertyID(), key: .init(rawValue: key), value: value, origin: origin))))
            }
        }
        guard !applicable.isEmpty else { throw FormInspectorError.noApplicableTarget }
        guard !commands.isEmpty else { throw FormInspectorError.noChanges }
        let command: DocumentCommand = commands.count == 1 ? commands[0] : .batch(commands)
        guard CommandRegistry().availability(for: command, in: document).isEnabled else { throw FormInspectorError.stale }
        return .init(command: command, applicableNodeIDs: applicable, skippedNodeIDs: skipped)
    }

    private func validate(_ value: FormFieldConfiguration) throws {
        guard !value.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.label.count <= 256,
              value.name.range(of: "^[A-Za-z][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil,
              value.help.map({ $0.count <= 512 && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }) ?? true else {
            throw FormInspectorError.invalidConfiguration
        }
        if value.kind == .select {
            do { try CanonicalFormSelectOptions.validate(value.options) }
            catch { throw FormInspectorError.invalidConfiguration }
        } else if !value.options.isEmpty {
            throw FormInspectorError.invalidConfiguration
        }
        if let maximumLength = value.maximumLength {
            guard [FormFieldKind.text, .email, .textarea].contains(value.kind),
                  (CanonicalFormField.minimumMaximumLength...CanonicalFormField.maximumMaximumLength).contains(maximumLength) else {
                throw FormInspectorError.invalidConfiguration
            }
        }
    }
}

// SF-1006 v1 local validation is deliberately a pure, ephemeral resolver.
// Visitor-entered values do not conform to Codable and never cross a command,
// history, package, autosave, or recovery boundary. The identity below binds a
// result to the adopted document scene without retaining private field values.
enum FormVisitorValue: Equatable, Sendable {
    case text(String)
    case checkbox(Bool)
    case select(String)
}

struct FormVisitorValueSnapshot: Equatable, Sendable {
    let documentID: DocumentID
    let pageID: PageID
    let formID: NodeID
    let revision: UInt64
    let sceneID: CanvasViewportSceneID
    let rendererGeneration: UInt64
    let values: [NodeID: FormVisitorValue]

    init(documentID: DocumentID, pageID: PageID, formID: NodeID, revision: UInt64,
         sceneID: CanvasViewportSceneID, rendererGeneration: UInt64,
         values: [NodeID: FormVisitorValue]) {
        self.documentID = documentID
        self.pageID = pageID
        self.formID = formID
        self.revision = revision
        self.sceneID = sceneID
        self.rendererGeneration = rendererGeneration
        self.values = values
    }
}

/// Stable, deterministic result identity. It identifies a field result, not a
/// visitor value, so logs and UI announcements can correlate validation safely.
struct FormValidationResultIdentity: Equatable, Hashable, Sendable, Identifiable {
    let documentID: DocumentID
    let revision: UInt64
    let formID: NodeID
    let fieldID: NodeID?

    var id: String {
        [documentID.description, String(revision), formID.description, fieldID?.description ?? "form"]
            .joined(separator: ":")
    }
}

enum FormValidationFailure: String, Equatable, Sendable {
    case required, invalidEmail, invalidSelection, invalidValueType, textTooLong, unsupportedField
}

struct FormFieldValidationResult: Equatable, Sendable, Identifiable {
    let identity: FormValidationResultIdentity
    let failures: [FormValidationFailure]

    var id: FormValidationResultIdentity { identity }
    var isValid: Bool { failures.isEmpty }
}

enum FormStaticOutputCompatibility: String, Equatable, Sendable {
    case compatibleStaticControl
    case unavailableSubmission
    case invalidSchema
}

struct FormValidationSnapshot: Equatable, Sendable {
    let identity: FormValidationResultIdentity
    let fields: [FormFieldValidationResult]
    let staticOutputCompatibility: FormStaticOutputCompatibility

    var isValid: Bool { fields.allSatisfy(\.isValid) }
}

enum FormValidationError: Error, Equatable, LocalizedError, Sendable {
    case cancelled, stale, unavailableForm, invalidSchema

    var errorDescription: String? {
        switch self {
        case .cancelled: "Form validation was cancelled; visitor values were not retained."
        case .stale: "Form validation is no longer current; review the live form and try again."
        case .unavailableForm: "This form is no longer available for local validation."
        case .invalidSchema: "This form has invalid field configuration; correct the field settings first."
        }
    }
}

/// Headless local form validation. This consumes only a caller-owned visitor
/// snapshot and canonical field configuration. It returns categories and stable
/// identities exclusively; raw values, labels, names, and options never appear
/// in errors or diagnostics.
struct LocalFormValidationEngine: Sendable {
    static let requirementIDs: Set<String> = Set((1...8).map { String(format: "SF-1006-%03d", $0) })
    static let maximumTextLength = 4_096

    func validate(_ input: FormVisitorValueSnapshot, in document: CanonicalDocument,
                  context: TransformValidationContext, cancelled: Bool = false) throws -> FormValidationSnapshot {
        guard !cancelled else { throw FormValidationError.cancelled }
        guard input.documentID == document.id, input.revision == document.revision,
              input.pageID == context.activePageID, input.sceneID == context.currentSceneID,
              input.rendererGeneration == context.rendererGeneration,
              context.isLifecycleAvailable else { throw FormValidationError.stale }
        guard let page = document.pages.first(where: { $0.id == input.pageID }),
              let form = page.nodes.first(where: { $0.id == input.formID }), form.kind == .form,
              context.availableNodeIDs.contains(form.id) else { throw FormValidationError.unavailableForm }
        guard !form.childIDs.isEmpty else { throw FormValidationError.invalidSchema }

        let nodes = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let fields = try form.childIDs.map { fieldID -> FormFieldValidationResult in
            guard let node = nodes[fieldID], node.kind == .text, case .node(let parent) = node.parent,
                  parent == form.id else { throw FormValidationError.invalidSchema }
            do { try CanonicalFormFieldValidator.validate(node) }
            catch { throw FormValidationError.invalidSchema }
            guard let kind = node.insertionStringProperty(CanonicalFormField.kindKey),
                  let required = node.insertionProperty(CanonicalFormField.requiredKey).flatMap({ property -> Bool? in
                      if case .boolean(let value) = property.value { return value }; return nil
                  }) else { throw FormValidationError.invalidSchema }
            let options: [CanonicalFormSelectOption]
            if kind == FormFieldKind.select.rawValue {
                guard let encoded = node.insertionStringProperty(CanonicalFormField.optionsKey) else {
                    throw FormValidationError.invalidSchema
                }
                do { options = try CanonicalFormSelectOptions.decode(encoded) }
                catch { throw FormValidationError.invalidSchema }
            } else { options = [] }
            return .init(
                identity: .init(documentID: document.id, revision: document.revision, formID: form.id, fieldID: fieldID),
                failures: failures(kind: kind, required: required, options: options,
                                   maximumLength: node.insertionNumberProperty(CanonicalFormField.maximumLengthKey).map { Int($0) },
                                   value: input.values[fieldID])
            )
        }
        return .init(
            identity: .init(documentID: document.id, revision: document.revision, formID: form.id, fieldID: nil),
            fields: fields,
            staticOutputCompatibility: .unavailableSubmission
        )
    }

    private func failures(kind: String, required: Bool, options: [CanonicalFormSelectOption], maximumLength: Int?,
                          value: FormVisitorValue?) -> [FormValidationFailure] {
        switch kind {
        case FormFieldKind.text.rawValue, FormFieldKind.textarea.rawValue, FormFieldKind.email.rawValue:
            guard let value else { return required ? [.required] : [] }
            guard case .text(let text) = value else { return [.invalidValueType] }
            let maximum = maximumLength ?? Self.maximumTextLength
            if text.count > maximum { return [.textTooLong] }
            if required && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [.required] }
            if kind == FormFieldKind.email.rawValue, !text.isEmpty, !Self.isValidEmail(text) { return [.invalidEmail] }
            return []
        case FormFieldKind.checkbox.rawValue:
            guard let value else { return required ? [.required] : [] }
            guard case .checkbox(let checked) = value else { return [.invalidValueType] }
            return required && !checked ? [.required] : []
        case FormFieldKind.select.rawValue:
            guard let value else { return required ? [.required] : [] }
            guard case .select(let selected) = value else { return [.invalidValueType] }
            if selected.isEmpty { return required ? [.required] : [] }
            return options.contains(where: { $0.value == selected }) ? [] : [.invalidSelection]
        case FormFieldKind.submit.rawValue:
            return []
        default:
            return [.unsupportedField]
        }
    }

    private static func isValidEmail(_ value: String) -> Bool {
        // Bounded local syntax check only; this intentionally does not perform
        // DNS, delivery, remote validation, normalization, or value logging.
        guard value.utf8.count <= 254,
              value.range(of: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", options: .regularExpression) != nil else { return false }
        return true
    }
}

enum LinkInspectorEdit: Equatable, Sendable {
    case label(String?)
    case target(CanonicalLinkTarget?)
    case context(CanonicalLinkContext?)
}

enum LinkInspectorError: Error, Equatable, LocalizedError, Sendable {
    case cancelled, emptySelection, staleDocument, staleRevision, staleRenderer,
         pageUnavailable, selectionMismatch, duplicateTarget, missingTarget,
         lockedTarget, hiddenTarget, unavailableTarget, noApplicableTarget, revisionExhausted
    var errorDescription: String? {
        switch self {
        case .cancelled: "Draft cancelled; committed properties are unchanged."
        case .emptySelection, .noApplicableTarget: "Select a Button or Link to edit its label and target."
        case .lockedTarget: "Unlock the selected control before editing."
        case .hiddenTarget, .unavailableTarget: "Show the selected control at this breakpoint before editing."
        case .revisionExhausted: "The document revision cannot accept another edit."
        default: "The document, selection, or renderer changed. Review the current control and try again."
        }
    }
}

struct LinkInspectorDiagnostic: Equatable, Sendable {
    let requirementID: String
    let operation: String
    let provenance: String
    let identifiers: [String]
    let durationMilliseconds: Double
    let succeeded: Bool
}

struct LinkInspectorCommandRegistry: Sendable {
    /// SF-0806-002/005, SF-1102-002/005. Existing property commands own the
    /// inverse, including removed property IDs and provenance.
    func prepare(
        _ edit: LinkInspectorEdit,
        identity: ImageInspectorOperationIdentity,
        in document: CanonicalDocument,
        context: TransformValidationContext,
        cancelled: Bool = false
    ) throws -> PreparedImageInspectorEdit {
        if cancelled { throw LinkInspectorError.cancelled }
        guard identity.documentID == document.id else { throw LinkInspectorError.staleDocument }
        guard identity.revision == document.revision else { throw LinkInspectorError.staleRevision }
        guard identity.sceneID == context.currentSceneID,
              identity.rendererGeneration == context.rendererGeneration else { throw LinkInspectorError.staleRenderer }
        guard context.isLifecycleAvailable else { throw TransformError.lifecycleUnavailable(context.lifecycleDisabledReason ?? "Editing is unavailable.") }
        guard identity.pageID == context.activePageID,
              let page = document.pages.first(where: { $0.id == identity.pageID }) else { throw LinkInspectorError.pageUnavailable }
        guard !identity.selectedNodeIDs.isEmpty else { throw LinkInspectorError.emptySelection }
        guard Set(identity.selectedNodeIDs).count == identity.selectedNodeIDs.count else { throw LinkInspectorError.duplicateTarget }
        guard identity.selectedNodeIDs == context.selectedNodeIDs else { throw LinkInspectorError.selectionMismatch }
        guard document.revision < UInt64.max - 1 else { throw LinkInspectorError.revisionExhausted }
        if case .label(let label?) = edit {
            guard label.utf8.count <= 4096, label.rangeOfCharacter(from: .controlCharacters) == nil else { throw CanonicalLinkError.invalidLabel }
        }
        if case .target(.external(let url)) = edit, !CanonicalLinkTarget.validateExternal(url) { throw CanonicalLinkError.invalidTarget }
        if case .target(let target?) = edit, target.isMissing(in: document) { throw CanonicalLinkError.invalidTarget }
        var commands: [DocumentCommand] = []
        var applicable: [NodeID] = [], skipped: [NodeID] = []
        for id in identity.selectedNodeIDs {
            guard let node = page.nodes.first(where: { $0.id == id }) else { throw LinkInspectorError.missingTarget }
            guard node.kind.isLinkControl else { skipped.append(id); continue }
            if node.insertionBooleanProperty("locked") { throw LinkInspectorError.lockedTarget }
            if node.insertionBooleanProperty("hidden") { throw LinkInspectorError.hiddenTarget }
            guard context.availableNodeIDs.contains(id) else { throw LinkInspectorError.unavailableTarget }
            applicable.append(id)
            let replacements: [(String, PropertyValue)]
            let owned: Set<String>
            let origin: PropertyOrigin
            switch edit {
            case .label(let label):
                replacements = label.map { [(CanonicalLinkTarget.labelKey, .string($0))] } ?? []
                owned = [CanonicalLinkTarget.labelKey]
                origin = label == nil ? .defaulted : .authored
            case .target(let target):
                replacements = target?.properties ?? []
                owned = Set(["kind", "pageID", "nodeID", "url"].map { CanonicalLinkTarget.namespace + $0 })
                origin = .authored
            case .context(let value):
                replacements = value.map { [(CanonicalLinkTarget.namespace + "context", .string($0.rawValue))] } ?? []
                owned = [CanonicalLinkTarget.namespace + "context"]
                origin = .authored
            }
            let keys = Set(replacements.map(\.0))
            for previous in node.properties where owned.contains(previous.key.rawValue) && !keys.contains(previous.key.rawValue) {
                commands.append(.removeProperty(.init(pageID: page.id, nodeID: id, propertyID: previous.id)))
            }
            for (key, value) in replacements {
                let previous = node.insertionProperty(key)
                if previous?.value == value && previous?.origin == origin { continue }
                commands.append(.setProperty(.init(pageID: page.id, nodeID: id,
                    property: .init(id: previous?.id ?? PropertyID(), key: .init(rawValue: key), value: value, origin: origin))))
            }
        }
        guard !applicable.isEmpty else { throw LinkInspectorError.noApplicableTarget }
        guard !commands.isEmpty else { throw ContainerLayoutError.noChanges }
        let command: DocumentCommand = commands.count == 1 ? commands[0] : .batch(commands)
        guard CommandRegistry().availability(for: command, in: document).isEnabled else { throw CanonicalLinkError.invalidTarget }
        return .init(command: command, applicableNodeIDs: applicable, skippedNodeIDs: skipped)
    }
}

struct ImageInspectorCommandRegistry: Sendable {
    func prepare(
        _ input: ImageInspectorCommand,
        in document: CanonicalDocument,
        context: TransformValidationContext,
        cancelled: Bool = false
    ) throws -> PreparedImageInspectorEdit {
        if cancelled { throw ImageInspectorError.cancelled }
        guard context.isLifecycleAvailable else { throw ImageInspectorError.unavailableTarget }
        let identity = input.identity
        guard identity.documentID == document.id else { throw ImageInspectorError.staleDocument }
        guard identity.revision == document.revision else { throw ImageInspectorError.staleRevision }
        guard identity.sceneID == context.currentSceneID,
              identity.rendererGeneration == context.rendererGeneration else {
            throw ImageInspectorError.staleRenderer
        }
        guard identity.pageID == context.activePageID,
              let page = document.pages.first(where: { $0.id == identity.pageID }) else {
            throw ImageInspectorError.pageUnavailable
        }
        guard !identity.selectedNodeIDs.isEmpty else { throw ImageInspectorError.emptySelection }
        guard Set(identity.selectedNodeIDs).count == identity.selectedNodeIDs.count else {
            throw ImageInspectorError.duplicateTarget
        }
        guard identity.selectedNodeIDs == context.selectedNodeIDs else {
            throw ImageInspectorError.selectionMismatch
        }
        guard document.revision < UInt64.max - 1 else { throw ImageInspectorError.revisionExhausted }
        try validate(input.edit, document: document)
        var commands: [DocumentCommand] = []
        var applicable: [NodeID] = []
        var skipped: [NodeID] = []
        for id in identity.selectedNodeIDs {
            guard let node = page.nodes.first(where: { $0.id == id }) else {
                throw ImageInspectorError.missingTarget
            }
            guard node.kind == .image else { skipped.append(id); continue }
            if node.insertionBooleanProperty("locked") { throw ImageInspectorError.lockedTarget }
            if node.insertionBooleanProperty("hidden") { throw ImageInspectorError.hiddenTarget }
            guard context.availableNodeIDs.contains(id) else { throw ImageInspectorError.unavailableTarget }
            applicable.append(id)
            let values: [(String, PropertyValue)] = switch input.edit {
            case .asset(let value): [(CanonicalImageStyle.namespace + "assetID", .string(value.description))]
            case .fit(let value): [(CanonicalImageStyle.namespace + "fit", .string(value.rawValue))]
            case .focal(let x, let y): [
                (CanonicalImageStyle.namespace + "focal.x", .number(x)),
                (CanonicalImageStyle.namespace + "focal.y", .number(y)),
            ]
            case .altText(let value): [(CanonicalImageStyle.namespace + "alt", .string(value))]
            case .decorative(let value): [(CanonicalImageStyle.namespace + "decorative", .boolean(value))]
            case .details(let x, let y, let alt):
                (x.map { [(CanonicalImageStyle.namespace + "focal.x", PropertyValue.number($0))] } ?? [])
                + (y.map { [(CanonicalImageStyle.namespace + "focal.y", PropertyValue.number($0))] } ?? [])
                + (alt.map { [(CanonicalImageStyle.namespace + "alt", PropertyValue.string($0))] } ?? [])
            }
            for (key, value) in values {
                let previous = node.insertionProperty(key)
                if previous?.value == value, previous?.origin == .authored { continue }
                commands.append(.setProperty(.init(
                    pageID: page.id,
                    nodeID: id,
                    property: NodeProperty(
                        id: previous?.id ?? PropertyID(),
                        key: .init(rawValue: key),
                        value: value,
                        origin: .authored
                    )
                )))
            }
        }
        guard !applicable.isEmpty else { throw ImageInspectorError.noApplicableTarget }
        if commands.isEmpty {
            return .init(command: .batch([]), applicableNodeIDs: applicable, skippedNodeIDs: skipped)
        }
        let command: DocumentCommand = commands.count == 1 ? commands[0] : .batch(commands)
        guard CommandRegistry().availability(for: command, in: document).isEnabled else {
            throw ImageInspectorError.missingTarget
        }
        return PreparedImageInspectorEdit(
            command: command,
            applicableNodeIDs: applicable,
            skippedNodeIDs: skipped
        )
    }

    private func validate(_ edit: ImageInspectorEdit, document: CanonicalDocument) throws {
        switch edit {
        case .asset(let id):
            guard document.imageAssets.contains(where: { $0.id == id }) else {
                throw ImageInspectorError.invalidAsset
            }
        case .focal(let x, let y):
            guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else {
                throw ImageInspectorError.invalidFocalPoint
            }
        case .altText(let value):
            guard value.utf8.count <= 4_096,
                  !value.unicodeScalars.contains(where: {
                      CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t"
                  }) else { throw ImageInspectorError.invalidAltText }
        case .details(let x, let y, let alt):
            guard (x == nil) == (y == nil), x != nil || alt != nil else { throw ImageInspectorError.invalidFocalPoint }
            if let x, let y { try validate(.focal(x: x, y: y), document: document) }
            if let alt { try validate(.altText(alt), document: document) }
        case .fit, .decorative: break
        }
    }
}
