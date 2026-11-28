import Foundation

extension CanonicalFlowGradient {
    static func gradient(on node: DocumentNode) -> CanonicalFillLayer? {
        let layers = DesignInspectorCommandRegistry.resolvedLayers(for: node).filter(\.isEnabled)
        guard layers.count == 1, let layer = layers.first,
              layer.kind == .linearGradient, layer.stops.count <= 64,
              CanonicalImageFill.resolve(node) == nil, LocalColorTokenBinding.id(for: node, target: .fill) == nil else { return nil }
        return layer
    }
}

/// Replaces only its closed namespace and preserves existing property IDs.
/// The normal command registry supplies lock/read-only/history/inverse policy.
enum DecorativeEffectPropertyCommands {
    static func replace(namespace: String, values: [String: PropertyValue], node: DocumentNode,
                        pageID: PageID) -> [DocumentCommand] {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix(namespace) }
        var commands: [DocumentCommand] = []
        for key in values.keys.sorted() {
            guard let value = values[key] else { continue }
            let old = owned.first { $0.key.rawValue == key }
            if old?.value != value || old?.origin != .authored {
                commands.append(.setProperty(.init(pageID: pageID, nodeID: node.id,
                    property: .init(id: old?.id ?? PropertyID(), key: .init(rawValue: key), value: value, origin: .authored))))
            }
        }
        for property in owned where values[property.key.rawValue] == nil {
            commands.append(.removeProperty(.init(pageID: pageID, nodeID: node.id, propertyID: property.id)))
        }
        return commands
    }
}

enum DecorativeEffectEdit: Sendable {
    case flow(CanonicalFlowGradient?)
    case glass(CanonicalGlassSurface?)
    /// OD-040: nil (or an empty value) removes the node's motion.
    case motion(CanonicalMotion?)
    /// OD-039: nil (or an empty graph) removes the node's interactions.
    case events(CanonicalEventGraph?)
    /// SF-1105: nil removes the overlay.
    case overlay(CanonicalOverlay?)
    /// SF-1106: nil removes the visibility condition.
    case visibility(CanonicalPageState.Condition?)
    /// SF-1106: page variables on the page Root; empty removes them.
    case pageVariables([CanonicalStateVariable])
    /// SF-1106 (C6, ADR-0066): a Text shows a page variable's value; nil removes the binding.
    case textBinding(CanonicalTextBinding?)
}

enum DecorativeEffectCommandRegistry {
    static func prepare(_ edit: DecorativeEffectEdit, identity: DesignInspectorOperationIdentity,
                        orderedNodeIDs: [NodeID], document: CanonicalDocument,
                        context: TransformValidationContext) throws -> PreparedDesignInspectorEdit {
        guard context.isLifecycleAvailable else { throw DesignInspectorError.unavailable("Wait for the document operation before editing effects.") }
        guard identity.documentID == document.id, identity.revision == document.revision,
              identity.pageID == context.activePageID, identity.sceneID == context.currentSceneID,
              identity.rendererGeneration == context.rendererGeneration,
              orderedNodeIDs == context.selectedNodeIDs, !orderedNodeIDs.isEmpty,
              Set(orderedNodeIDs).count == orderedNodeIDs.count,
              let page = document.pages.first(where: { $0.id == identity.pageID }) else { throw DesignInspectorError.stale }
        let namespace: String, values: [String: PropertyValue], kinds: Set<NodeKind>
        switch edit {
        case .flow(let flow):
            guard flow?.isValid ?? true else { throw DesignBoxStyleError.invalidValue }
            namespace = CanonicalFlowGradient.namespace; values = flow?.properties ?? [:]; kinds = [.frame, .section]
        case .glass(let glass):
            guard glass?.isValid ?? true else { throw DesignBoxStyleError.invalidValue }
            namespace = CanonicalGlassSurface.namespace; values = glass?.properties ?? [:]; kinds = [.frame, .section, .stack, .grid, .button]
        case .motion(let motion):
            guard motion?.isValid ?? true else { throw DesignBoxStyleError.invalidValue }
            namespace = CanonicalMotion.prefix; values = motion?.properties ?? [:]; kinds = CanonicalMotion.supportedKinds
        case .events(let graph):
            guard graph?.isValid ?? true else { throw DesignBoxStyleError.invalidValue }
            namespace = CanonicalEventGraph.prefix; values = graph?.properties ?? [:]; kinds = CanonicalEventGraph.supportedKinds
        case .overlay(let overlay):
            namespace = CanonicalOverlay.prefix; values = overlay?.properties ?? [:]; kinds = CanonicalOverlay.supportedKinds
        case .visibility(let condition):
            guard condition?.equals.isValid ?? true else { throw DesignBoxStyleError.invalidValue }
            namespace = CanonicalPageState.visibleWhenKey; values = condition.map { CanonicalPageState.properties(condition: $0) } ?? [:]
            kinds = CanonicalEventGraph.supportedKinds
        case .pageVariables(let variables):
            guard CanonicalPageState.isValid(variables) else { throw DesignBoxStyleError.invalidValue }
            namespace = CanonicalPageState.variablesKey; values = CanonicalPageState.properties(variables: variables); kinds = [.frame]
        case .textBinding(let binding):
            // A new or re-pointed binding names a variable this page has; one that
            // stopped resolving can still be removed.
            if let binding, !CanonicalPageState.variables(on: page).contains(where: { $0.id == binding.variable }) {
                throw DesignInspectorError.unavailable(CanonicalTextBinding.missingVariableReason)
            }
            namespace = CanonicalTextBinding.key; values = binding.map { CanonicalTextBinding.properties($0) } ?? [:]; kinds = [.text]
        }
        var stateReason: String? = nil
        switch edit {
        case .overlay: stateReason = CanonicalOverlay.unsupportedReason
        case .visibility: stateReason = CanonicalEventGraph.unsupportedReason
        case .pageVariables: stateReason = CanonicalPageState.variablesReason
        case .textBinding: stateReason = CanonicalTextBinding.unsupportedReason
        default: break
        }
        let isState = stateReason != nil
        let rootID = PageBackgroundPolicy.root(in: page)?.id
        let isMotion: Bool, isEvents: Bool
        if case .motion = edit { isMotion = true } else { isMotion = false }
        if case .events = edit { isEvents = true } else { isEvents = false }
        let unsupportedReason: String? = isMotion ? CanonicalMotion.unsupportedReason : isEvents ? CanonicalEventGraph.unsupportedReason : stateReason
        var applied: [NodeID] = [], skipped: [NodeID] = [], reasons: [NodeID: String] = [:], commands: [DocumentCommand] = []
        for id in orderedNodeIDs {
            guard let node = page.nodes.first(where: { $0.id == id }), context.availableNodeIDs.contains(id),
                  !node.selectionBooleanProperty("locked"), !node.selectionBooleanProperty("hidden") else { throw DesignInspectorError.stale }
            guard kinds.contains(node.kind) else { skipped.append(id);reasons[id] = unsupportedReason ?? "This object kind does not support this effect.";continue }
            if isMotion || isEvents, node.properties.contains(where: { $0.key.rawValue.hasPrefix("form.field.v1.") }) {
                skipped.append(id); reasons[id] = isMotion ? "Form fields do not support motion." : "Form fields do not support interactions."; continue
            }
            if isState {
                if case .pageVariables = edit {
                    guard id == rootID else { skipped.append(id); reasons[id] = CanonicalPageState.variablesReason; continue }
                } else if id == rootID {
                    skipped.append(id); reasons[id] = CanonicalPageState.rootReason; continue
                }
                if node.properties.contains(where: { $0.key.rawValue.hasPrefix("form.field.v1.") }) {
                    skipped.append(id); reasons[id] = "Form fields do not support this setting."; continue
                }
            }
            if case .events(let graph?) = edit, !graph.isAllowed(on: node.kind) {
                skipped.append(id); reasons[id] = CanonicalEventGraph.clickReason; continue
            }
            if case .flow(let flow) = edit, flow?.enabled == true, CanonicalFlowGradient.gradient(on: node) == nil {
                throw DesignInspectorError.unavailable(CanonicalFlowGradient.unavailableReason)
            }
            applied.append(id)
            commands += DecorativeEffectPropertyCommands.replace(namespace: namespace, values: values, node: node, pageID: page.id)
        }
        let onlyReason: String? = (isMotion || isEvents || isState) && Set(reasons.values).count == 1 ? reasons.values.first : nil
        guard !applied.isEmpty else { throw DesignInspectorError.unavailable(onlyReason ?? unsupportedReason ?? "Select a supported Frame, Section or container to edit this effect.") }
        guard !commands.isEmpty else { throw DesignInspectorError.noChanges }
        let batch = DocumentCommand.batch(commands)
        let availability = CommandRegistry().availability(for: batch, in: document)
        guard availability.isEnabled else { throw DesignInspectorError.unavailable(availability.disabledReason ?? "This effect cannot be applied in the current context.") }
        return .init(applicableNodeIDs: applied, skippedNodeIDs: skipped, skippedReasons: reasons, documentCommand: batch)
    }
}



/// OD-040 / SF-1103 / SF-1104 (ADR-0060): CSS-first motion. A node may own
/// one state-change transition and one reveal-on-scroll entrance. Each group
/// is all-or-nothing in the closed `motion.v1.` namespace; an omitted group
/// means no motion. Scroll position, observers and animation progress are
/// runtime state and never enter the document.
struct CanonicalMotion: Equatable, Sendable {
    enum Easing: String, CaseIterable, Sendable {
        case ease, linear
        case easeIn = "ease-in", easeOut = "ease-out", easeInOut = "ease-in-out"
        var label: String {
            switch self {
            case .ease: "Ease"
            case .linear: "Linear"
            case .easeIn: "Ease In"
            case .easeOut: "Ease Out"
            case .easeInOut: "Ease In and Out"
            }
        }
    }
    enum EntranceEffect: String, CaseIterable, Sendable {
        case fade, rise, zoom
        case slideFromLeft = "slide-from-left", slideFromRight = "slide-from-right"
        var label: String {
            switch self {
            case .fade: "Fade In"
            case .rise: "Rise"
            case .zoom: "Zoom In"
            case .slideFromLeft: "Slide From Left"
            case .slideFromRight: "Slide From Right"
            }
        }
        /// Fade and zoom do not move; their authored distance is kept unchanged.
        var usesDistance: Bool { self == .rise || self == .slideFromLeft || self == .slideFromRight }
    }
    struct Transition: Equatable, Sendable {
        var milliseconds: Double
        var easing: Easing
        var isValid: Bool { CanonicalMotion.whole(milliseconds, in: 50...2_000) }
    }
    struct Entrance: Equatable, Sendable {
        var effect: EntranceEffect
        var milliseconds: Double
        var delayMilliseconds: Double
        /// Travel in CSS pixels for the rise and slide effects.
        var distance: Double
        /// The trigger line, in percent of the viewport height above its bottom edge.
        var offsetPercent: Double
        var easing: Easing
        var isValid: Bool {
            CanonicalMotion.whole(milliseconds, in: 100...3_000) && CanonicalMotion.whole(delayMilliseconds, in: 0...3_000)
                && CanonicalMotion.whole(distance, in: 0...400) && CanonicalMotion.whole(offsetPercent, in: 0...50)
        }
    }

    static let prefix = "motion."
    static let namespace = "motion.v1."
    static let transitionNamespace = namespace + "transition."
    static let entranceNamespace = namespace + "entrance."
    /// Motion shares document schema 27 with container queries (not released).
    static let documentSchema = 27
    static let supportedKinds: Set<NodeKind> = [.frame, .text, .section, .stack, .grid, .image, .button, .link]
    static let transitionKeys: Set<String> = Set(["duration", "easing"].map { CanonicalMotion.transitionNamespace + $0 })
    static let entranceKeys: Set<String> = Set(["effect", "duration", "delay", "distance", "offset", "easing"].map { CanonicalMotion.entranceNamespace + $0 })
    static let defaultTransition = Transition(milliseconds: 200, easing: .ease)
    static let defaultEntrance = Entrance(effect: .rise, milliseconds: 600, delayMilliseconds: 0, distance: 24, offsetPercent: 15, easing: .easeOut)
    static let unsupportedReason = "Motion is available on frames, sections, stacks, grids, text, images, buttons and links."

    var transition: Transition? = nil
    var entrance: Entrance? = nil
    var isEmpty: Bool { transition == nil && entrance == nil }
    var isValid: Bool { (transition?.isValid ?? true) && (entrance?.isValid ?? true) }

    static func whole(_ value: Double, in range: ClosedRange<Double>) -> Bool {
        value.isFinite && range.contains(value) && value.rounded() == value
    }

    var properties: [String: PropertyValue] {
        var values: [String: PropertyValue] = [:]
        if let transition {
            values[Self.transitionNamespace + "duration"] = .number(transition.milliseconds)
            values[Self.transitionNamespace + "easing"] = .string(transition.easing.rawValue)
        }
        if let entrance {
            values[Self.entranceNamespace + "effect"] = .string(entrance.effect.rawValue)
            values[Self.entranceNamespace + "duration"] = .number(entrance.milliseconds)
            values[Self.entranceNamespace + "delay"] = .number(entrance.delayMilliseconds)
            values[Self.entranceNamespace + "distance"] = .number(entrance.distance)
            values[Self.entranceNamespace + "offset"] = .number(entrance.offsetPercent)
            values[Self.entranceNamespace + "easing"] = .string(entrance.easing.rawValue)
        }
        return values
    }

    /// Unknown versions, partial groups, wrong value types, out-of-range or
    /// fractional values and unsupported node kinds are rejected, never ignored.
    static func resolve(_ node: DocumentNode) throws -> Self? {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix(prefix) }
        guard !owned.isEmpty else { return nil }
        let keys = Set(owned.map(\.key.rawValue))
        var expected = Set<String>()
        if keys.contains(where: { $0.hasPrefix(transitionNamespace) }) { expected.formUnion(transitionKeys) }
        if keys.contains(where: { $0.hasPrefix(entranceNamespace) }) { expected.formUnion(entranceKeys) }
        guard supportedKinds.contains(node.kind), keys == expected, owned.count == keys.count else {
            throw ModelValidationError.invalidMotionState
        }
        var result = Self()
        if !keys.isDisjoint(with: transitionKeys) {
            guard let duration = node.insertionNumberProperty(transitionNamespace + "duration"),
                  let easing = node.insertionStringProperty(transitionNamespace + "easing").flatMap(Easing.init(rawValue:)) else {
                throw ModelValidationError.invalidMotionState
            }
            result.transition = Transition(milliseconds: duration, easing: easing)
        }
        if !keys.isDisjoint(with: entranceKeys) {
            guard let effect = node.insertionStringProperty(entranceNamespace + "effect").flatMap(EntranceEffect.init(rawValue:)),
                  let duration = node.insertionNumberProperty(entranceNamespace + "duration"),
                  let delay = node.insertionNumberProperty(entranceNamespace + "delay"),
                  let distance = node.insertionNumberProperty(entranceNamespace + "distance"),
                  let offset = node.insertionNumberProperty(entranceNamespace + "offset"),
                  let easing = node.insertionStringProperty(entranceNamespace + "easing").flatMap(Easing.init(rawValue:)) else {
                throw ModelValidationError.invalidMotionState
            }
            result.entrance = Entrance(effect: effect, milliseconds: duration, delayMilliseconds: delay,
                                       distance: distance, offsetPercent: offset, easing: easing)
        }
        guard result.isValid else { throw ModelValidationError.invalidMotionState }
        return result
    }
}

/// OD-040 output. Each emitted CSS line is one complete rule, so the release
/// profile's line de-duplication can never split a block. Everything sits
/// behind `prefers-reduced-motion:no-preference`; entrance hiding also needs
/// the runtime's `sf-motion-ready` class, so content stays visible without
/// JavaScript, in print and with Reduce Motion.
enum MotionOutput {
    static func entrances(_ page: DocumentPage) throws -> [NodeID: Int] {
        var result: [NodeID: Int] = [:]
        for node in page.nodes {
            if let entrance = try CanonicalMotion.resolve(node)?.entrance { result[node.id] = Int(entrance.offsetPercent) }
        }
        return result
    }

    static func usesMotion(_ page: DocumentPage) throws -> Bool {
        try page.nodes.contains { try CanonicalMotion.resolve($0) != nil }
    }

    static func css(_ nodes: [DocumentNode]) throws -> String {
        var lines: [String] = []
        for node in nodes.sorted(by: { $0.id.description < $1.id.description }) {
            guard let motion = try CanonicalMotion.resolve(node) else { continue }
            let name = node.id.description, selector = ".sf-node-" + name
            if let transition = motion.transition {
                lines.append("@media (prefers-reduced-motion:no-preference) { \(selector) { transition-property:background-color,opacity; transition-duration:\(Int(transition.milliseconds))ms; transition-timing-function:\(transition.easing.rawValue); } }")
            }
            if let entrance = motion.entrance {
                lines.append("@keyframes sf-entrance-\(name) { from { \(keyframe(entrance)) } }")
                lines.append("@media screen and (prefers-reduced-motion:no-preference) { .sf-motion-ready \(selector)[data-siteforge-entrance]:not(.sf-motion-entered) { opacity:0; } }")
                lines.append("@media screen and (prefers-reduced-motion:no-preference) { .sf-motion-ready \(selector).sf-motion-entered { animation:sf-entrance-\(name) \(Int(entrance.milliseconds))ms \(entrance.easing.rawValue) \(Int(entrance.delayMilliseconds))ms both; } }")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Only opacity and transform move, so layout never shifts (SF-1104).
    static func keyframe(_ entrance: CanonicalMotion.Entrance) -> String {
        let distance = Int(entrance.distance)
        switch entrance.effect {
        case .fade: return "opacity:0;"
        case .rise: return "opacity:0;transform:translate3d(0,\(distance)px,0);"
        case .slideFromLeft: return "opacity:0;transform:translate3d(-\(distance)px,0,0);"
        case .slideFromRight: return "opacity:0;transform:translate3d(\(distance)px,0,0);"
        case .zoom: return "opacity:0;transform:scale(0.92);"
        }
    }
}

enum MotionRuntime {
    static let javascript = #"""
/* SiteForge motion runtime (OD-040). It only reveals elements; every value was validated by the build. */
(() => {
  'use strict';
  const pending = new Set(document.querySelectorAll('[data-siteforge-entrance]'));
  if (!pending.size) return;
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  const observers = new Map();
  let frame = 0;
  // ADR-0065: on a page without page flow a container's contents are separate elements that
  // name it (`data-siteforge-within`); they reveal with it.
  const members = element => {
    const id = element.getAttribute('data-siteforge-node') || '';
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id)
      ? Array.from(document.querySelectorAll('[data-siteforge-within~="' + id + '"]')) : [];
  };
  const reveal = element => {
    if (!pending.delete(element)) return;
    element.classList.add('sf-motion-entered');
    for (const observer of observers.values()) observer.unobserve(element);
    for (const member of members(element)) { if (pending.has(member)) reveal(member); else member.classList.add('sf-motion-entered'); }
  };
  const finish = () => {
    if (pending.size) return;
    for (const observer of observers.values()) observer.disconnect();
    observers.clear();
    removeEventListener('scroll', schedule); removeEventListener('resize', schedule);
    document.removeEventListener('focusin', focus, true); reduce.removeEventListener('change', changed);
    if (frame) cancelAnimationFrame(frame);
    frame = 0;
  };
  const revealAll = () => { for (const element of Array.from(pending)) reveal(element); finish(); };
  // The last screen of a page can never cross a trigger line: reveal what is left.
  const check = () => { frame = 0; if (innerHeight + scrollY >= document.documentElement.scrollHeight - 2) revealAll(); };
  function schedule() { if (!frame) frame = requestAnimationFrame(check); }
  // Keyboard focus never lands inside content that is still hidden.
  function focus(event) { for (const element of Array.from(pending)) if ([element].concat(members(element)).some(part => part.contains(event.target))) reveal(element); finish(); }
  function changed() { if (reduce.matches) revealAll(); }
  if (reduce.matches || typeof IntersectionObserver !== 'function') { revealAll(); return; }
  for (const element of pending) {
    const value = Number(element.getAttribute('data-siteforge-entrance'));
    const offset = Number.isInteger(value) && value >= 0 && value <= 50 ? value : 0;
    let observer = observers.get(offset);
    if (!observer) {
      observer = new IntersectionObserver(entries => {
        for (const entry of entries) if (entry.isIntersecting) reveal(entry.target);
        finish();
      }, {rootMargin: offset ? '0px 0px -' + offset + '% 0px' : '0px', threshold: 0});
      observers.set(offset, observer);
    }
    observer.observe(element);
  }
  addEventListener('scroll', schedule, {passive: true});
  addEventListener('resize', schedule, {passive: true});
  document.addEventListener('focusin', focus, true);
  reduce.addEventListener('change', changed);
  document.documentElement.classList.add('sf-motion-ready');
  schedule();
})();

"""#
}

/// OD-039 / SF-1101 (ADR-0061): a declarative event graph stored on the
/// trigger node. Each interaction is one trigger and an ordered list of fixed
/// SiteForge actions; no authored script exists. Targets that are later
/// deleted are kept as references and diagnosed at build time.
struct CanonicalInteraction: Codable, Equatable, Sendable, Identifiable {
    enum Trigger: String, Codable, CaseIterable, Sendable {
        case click
        case pointerEnter = "pointer-enter", pointerLeave = "pointer-leave"
        case focusIn = "focus-in", focusOut = "focus-out"
        case pageLoad = "page-load", viewportEnter = "viewport-enter"
        /// C7 (ADR-0066): a key pressed while the object itself has keyboard focus.
        case keyEnter = "key-enter", keyEscape = "key-escape"
        case keyArrowUp = "key-arrow-up", keyArrowDown = "key-arrow-down"
        case keyArrowLeft = "key-arrow-left", keyArrowRight = "key-arrow-right"
        var label: String {
            switch self {
            case .click: "Click"
            case .pointerEnter: "Pointer Enters"
            case .pointerLeave: "Pointer Leaves"
            case .focusIn: "Focus In"
            case .focusOut: "Focus Out"
            case .pageLoad: "Page Loads"
            case .viewportEnter: "Scrolled Into View"
            case .keyEnter: "Enter Key Pressed"
            case .keyEscape: "Escape Key Pressed"
            case .keyArrowUp: "Up Arrow Key Pressed"
            case .keyArrowDown: "Down Arrow Key Pressed"
            case .keyArrowLeft: "Left Arrow Key Pressed"
            case .keyArrowRight: "Right Arrow Key Pressed"
            }
        }
        /// The `KeyboardEvent.key` value of a key-press trigger; nil for the others.
        var keyboardKey: String? {
            switch self {
            case .keyEnter: "Enter"
            case .keyEscape: "Escape"
            case .keyArrowUp: "ArrowUp"
            case .keyArrowDown: "ArrowDown"
            case .keyArrowLeft: "ArrowLeft"
            case .keyArrowRight: "ArrowRight"
            case .click, .pointerEnter, .pointerLeave, .focusIn, .focusOut, .pageLoad, .viewportEnter: nil
            }
        }
    }
    enum ActionKind: String, Codable, CaseIterable, Sendable {
        case show, hide, toggle, focus
        case scrollTo = "scroll-to", navigate
        /// SF-1106 / SF-1105 (ADR-0062).
        case setVariable = "set-variable", toggleVariable = "toggle-variable"
        case openOverlay = "open-overlay", closeOverlay = "close-overlay"
        var label: String {
            switch self {
            case .show: "Show"
            case .hide: "Hide"
            case .toggle: "Show or Hide"
            case .focus: "Move Focus To"
            case .scrollTo: "Scroll To"
            case .navigate: "Go To Page"
            case .setVariable: "Set Variable"
            case .toggleVariable: "Flip True or False Variable"
            case .openOverlay: "Open Overlay"
            case .closeOverlay: "Close Overlay"
            }
        }
        var needsTarget: Bool { ![.navigate, .setVariable, .toggleVariable].contains(self) }
        var usesVariable: Bool { self == .setVariable || self == .toggleVariable }
    }
    struct Action: Codable, Equatable, Sendable {
        var kind: ActionKind
        var target: NodeID? = nil
        var page: PageID? = nil
        var variable: UUID? = nil
        var value: CanonicalVariableValue? = nil
        var isValid: Bool {
            switch kind {
            case .navigate: page != nil && target == nil && variable == nil && value == nil
            case .setVariable: variable != nil && value?.isValid == true && target == nil && page == nil
            case .toggleVariable: variable != nil && value == nil && target == nil && page == nil
            default: target != nil && page == nil && variable == nil && value == nil
            }
        }
    }
    var id: UUID
    var trigger: Trigger
    var actions: [Action]
    var isValid: Bool { (1...CanonicalEventGraph.maximumActions).contains(actions.count) && actions.allSatisfy(\.isValid) }
}

struct CanonicalEventGraph: Equatable, Sendable {
    static let prefix = "event."
    static let namespace = "event.v1."
    static let interactionsKey = namespace + "interactions"
    static let startsHiddenKey = namespace + "startsHidden"
    /// The event graph shares document schema 27 (not released).
    static let documentSchema = 27
    static let maximumInteractions = 8
    static let maximumActions = 8
    static let maximumEncodedBytes = 16_384
    static let supportedKinds: Set<NodeKind> = [.frame, .text, .section, .stack, .grid, .image, .button, .link]
    /// Click is limited to natively keyboard-operable controls (SF-1101-006).
    static let clickKinds: Set<NodeKind> = [.button, .link]
    static let clickReason = "Click interactions need a button or link, so keyboard and VoiceOver users can use them too."
    static let unsupportedReason = "Interactions are available on frames, sections, stacks, grids, text, images, buttons and links."
    /// C7 (ADR-0066): key presses need keyboard focus. Buttons and links have
    /// it; any other object is added to the Tab order (`tabindex="0"`) and Check
    /// Website warns, because a button or link is announced better.
    static let keyFocusNote = "Key presses run while this object has keyboard focus, so the website adds it to the Tab order. A button or link works better with VoiceOver; otherwise give this object an Accessible name."

    var interactions: [CanonicalInteraction] = []
    var startsHidden = false
    var isEmpty: Bool { interactions.isEmpty && !startsHidden }
    var isValid: Bool {
        interactions.count <= Self.maximumInteractions && Set(interactions.map(\.id)).count == interactions.count
            && interactions.allSatisfy(\.isValid) && (Self.encode(interactions)?.utf8.count ?? .max) <= Self.maximumEncodedBytes
    }
    func isAllowed(on kind: NodeKind) -> Bool {
        Self.supportedKinds.contains(kind) && (Self.clickKinds.contains(kind) || !interactions.contains { $0.trigger == .click })
    }

    /// Canonical text: sorted keys, no escaped slashes. Decoding requires it.
    static func encode(_ interactions: [CanonicalInteraction]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(interactions)).flatMap { String(data: $0, encoding: .utf8) }
    }

    var properties: [String: PropertyValue] {
        var values: [String: PropertyValue] = [:]
        if !interactions.isEmpty, let text = Self.encode(interactions) { values[Self.interactionsKey] = .string(text) }
        if startsHidden { values[Self.startsHiddenKey] = .boolean(true) }
        return values
    }

    static func resolve(_ node: DocumentNode) throws -> Self? {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix(prefix) }
        guard !owned.isEmpty else { return nil }
        guard owned.allSatisfy({ $0.key.rawValue == interactionsKey || $0.key.rawValue == startsHiddenKey }) else {
            throw ModelValidationError.invalidInteractionGraphState
        }
        var result = Self()
        if let property = node.insertionProperty(interactionsKey) {
            guard case .string(let text) = property.value else { throw ModelValidationError.invalidInteractionGraphState }
            result.interactions = try decode(text)
            guard !result.interactions.isEmpty else { throw ModelValidationError.invalidInteractionGraphState }
        }
        if let property = node.insertionProperty(startsHiddenKey) {
            guard case .boolean(true) = property.value else { throw ModelValidationError.invalidInteractionGraphState }
            result.startsHidden = true
        }
        guard result.isValid, result.isAllowed(on: node.kind) else { throw ModelValidationError.invalidInteractionGraphState }
        return result
    }

    /// Exact keys only (`id`, `trigger`, `actions`; `kind` plus optional
    /// `target` or `page`), bounded size, canonical text.
    static func decode(_ text: String) throws -> [CanonicalInteraction] {
        let data = Data(text.utf8)
        guard data.count <= maximumEncodedBytes,
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              raw.allSatisfy({ item in
                  guard Set(item.keys) == ["id", "trigger", "actions"], let actions = item["actions"] as? [[String: Any]] else { return false }
                  return actions.allSatisfy({ action in action["kind"] != nil && Set(action.keys).isSubset(of: ["kind", "target", "page", "variable", "value"]) })
              }),
              let value = try? JSONDecoder().decode([CanonicalInteraction].self, from: data),
              encode(value) == text else {
            throw ModelValidationError.invalidInteractionGraphState
        }
        return value
    }
}

extension CanonicalEventGraph {
    /// SF-1101-005: copying objects (paste, duplicate, page duplicate, making
    /// a component, component instances, slot contents) keeps interactions
    /// pointed at the copies. A target in `nodeMap` follows its copy and a
    /// Go To Page action in `pageMap` follows its page; other targets stay as
    /// they are and Check Website reports any that no longer exist. A copy
    /// gets its own interaction identities; a derived projection (a resolved
    /// component instance) keeps them, so output stays deterministic. Anything
    /// that is not a valid interactions value is returned unchanged.
    static func remappingTargets(_ value: PropertyValue, nodeMap: [NodeID: NodeID],
                                 pageMap: [PageID: PageID] = [:], freshIdentity: Bool = true) -> PropertyValue {
        guard case .string(let text) = value, var interactions = try? decode(text) else { return value }
        for index in interactions.indices {
            if freshIdentity { interactions[index].id = UUID() }
            for action in interactions[index].actions.indices {
                if let target = interactions[index].actions[action].target, let mapped = nodeMap[target] {
                    interactions[index].actions[action].target = mapped
                }
                if let page = interactions[index].actions[action].page, let mapped = pageMap[page] {
                    interactions[index].actions[action].page = mapped
                }
            }
        }
        guard let encoded = encode(interactions) else { return value }
        return .string(encoded)
    }
}

/// Compiled, validated runtime data for one trigger node: action kinds,
/// lowercase node identifiers and build-relative routes only.
struct EventOutputConfiguration: Codable, Equatable, Sendable {
    struct Action: Codable, Equatable, Sendable {
        let kind: String
        var target: String? = nil
        var href: String? = nil
        var variable: String? = nil
        var value: CanonicalVariableValue? = nil
    }
    let trigger: String
    let actions: [Action]
    static func json(_ interactions: [EventOutputConfiguration]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(data: (try? encoder.encode(interactions)) ?? Data(), encoding: .utf8) ?? "[]"
    }
}

/// OD-039 / SF-1106 (ADR-0062): a typed runtime value. Numbers are whole
/// (at most one billion in size) so the stored text has one canonical form.
enum CanonicalVariableValue: Codable, Hashable, Sendable {
    case boolean(Bool), number(Double), string(String)
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else { self = .string(try container.decode(String.self)) }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .boolean(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
    var type: CanonicalStateVariable.ValueType {
        switch self {
        case .boolean: .boolean
        case .number: .number
        case .string: .string
        }
    }
    var isValid: Bool {
        switch self {
        case .boolean: true
        case .number(let value): value.isFinite && value.rounded() == value && abs(value) <= 1_000_000_000
        case .string(let value): value.utf8.count <= 256 && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        }
    }
    var text: String {
        switch self {
        case .boolean(let value): value ? "true" : "false"
        case .number(let value): String(Int(value))
        case .string(let value): value
        }
    }
}

/// One page variable. Scope is the page; values reset on every page load
/// (no storage, so no consent is needed in this slice).
struct CanonicalStateVariable: Codable, Equatable, Sendable, Identifiable {
    enum ValueType: String, Codable, CaseIterable, Sendable {
        case boolean, number, string
        var label: String {
            switch self {
            case .boolean: "True or False"
            case .number: "Whole Number"
            case .string: "Text"
            }
        }
        var defaultValue: CanonicalVariableValue {
            switch self {
            case .boolean: .boolean(false)
            case .number: .number(0)
            case .string: .string("")
            }
        }
    }
    var id: UUID
    var name: String
    var type: ValueType
    var initial: CanonicalVariableValue
    var isValid: Bool { Self.validName(name) && initial.type == type && initial.isValid }
    static func validName(_ name: String) -> Bool {
        !name.isEmpty && name == name.trimmingCharacters(in: .whitespacesAndNewlines) && name.utf8.count <= 64
            && !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

/// Page variables live on the page Root (`state.v1.variables`); any other
/// supported object may be visible only while a variable equals a value
/// (`state.v1.visibleWhen`). Both are canonical JSON text with exact keys.
enum CanonicalPageState {
    struct Condition: Codable, Equatable, Sendable {
        var variable: UUID
        var equals: CanonicalVariableValue
    }
    static let prefix = "state."
    static let namespace = "state.v1."
    static let variablesKey = namespace + "variables"
    static let visibleWhenKey = namespace + "visibleWhen"
    static let documentSchema = 27
    static let maximumVariables = 16
    static let maximumEncodedBytes = 16_384
    static let variablesReason = "Page variables belong to the page. Select the page background to edit them."
    static let rootReason = "The page Root cannot be an overlay or have a visibility condition."

    static func encode<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func isValid(_ variables: [CanonicalStateVariable]) -> Bool {
        variables.count <= maximumVariables && variables.allSatisfy(\.isValid)
            && Set(variables.map(\.id)).count == variables.count && Set(variables.map(\.name)).count == variables.count
            && (encode(variables)?.utf8.count ?? .max) <= maximumEncodedBytes
    }

    static func properties(variables: [CanonicalStateVariable]) -> [String: PropertyValue] {
        guard !variables.isEmpty, let text = encode(variables) else { return [:] }
        return [variablesKey: .string(text)]
    }

    static func properties(condition: Condition) -> [String: PropertyValue] {
        guard let text = encode(condition) else { return [:] }
        return [visibleWhenKey: .string(text)]
    }

    static func storedVariables(_ node: DocumentNode) throws -> [CanonicalStateVariable] {
        guard let property = node.insertionProperty(variablesKey) else { return [] }
        guard case .string(let text) = property.value else { throw ModelValidationError.invalidRuntimeState }
        let data = Data(text.utf8)
        guard data.count <= maximumEncodedBytes,
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              raw.allSatisfy({ Set($0.keys) == ["id", "name", "type", "initial"] }),
              let value = try? JSONDecoder().decode([CanonicalStateVariable].self, from: data),
              !value.isEmpty, isValid(value), encode(value) == text else {
            throw ModelValidationError.invalidRuntimeState
        }
        return value
    }

    static func condition(_ node: DocumentNode) throws -> Condition? {
        guard let property = node.insertionProperty(visibleWhenKey) else { return nil }
        guard case .string(let text) = property.value else { throw ModelValidationError.invalidRuntimeState }
        let data = Data(text.utf8)
        guard data.count <= 1_024,
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(raw.keys) == ["equals", "variable"],
              let value = try? JSONDecoder().decode(Condition.self, from: data),
              value.equals.isValid, encode(value) == text else {
            throw ModelValidationError.invalidRuntimeState
        }
        return value
    }

    /// The page's variables, or none when the Root has none (or invalid data).
    static func variables(on page: DocumentPage) -> [CanonicalStateVariable] {
        guard let id = page.rootNodeIDs.first, let root = page.nodes.first(where: { $0.id == id }) else { return [] }
        return (try? storedVariables(root)) ?? []
    }

    /// References to removed variables are kept and diagnosed at build time.
    static func validate(_ node: DocumentNode, isPageRoot: Bool) throws {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix(prefix) }
        guard owned.allSatisfy({ [variablesKey, visibleWhenKey, CanonicalTextBinding.key].contains($0.key.rawValue) }) else {
            throw ModelValidationError.invalidRuntimeState
        }
        _ = try storedVariables(node)
        _ = try condition(node)
        _ = try CanonicalTextBinding.resolve(node)
        if node.insertionProperty(variablesKey) != nil, !isPageRoot { throw ModelValidationError.invalidRuntimeState }
        if node.insertionProperty(visibleWhenKey) != nil, isPageRoot || !CanonicalEventGraph.supportedKinds.contains(node.kind) {
            throw ModelValidationError.invalidRuntimeState
        }
        if try CanonicalOverlay.resolve(node) != nil, isPageRoot { throw ModelValidationError.invalidOverlayState }
    }
}

/// OD-039 / SF-1106-002 (C6, ADR-0066): a Text shows a page variable's value.
/// Stored on the Text as canonical JSON with one key: `state.v1.text` =
/// `{"variable":"<UUID>"}`. The text's own content and its translations stay
/// in the document: the canvas shows them, and the website shows them when
/// the page has no such variable (it was removed, or the Text was copied to
/// another page; Check Website reports it). While the variable exists the
/// website writes its starting value into the static HTML in every language
/// and on every item or list page, so the page reads correctly without
/// scripts, and the runtime replaces the text when the value changes. Values
/// use the variables' canonical text: whole numbers without grouping, text
/// as is, `true` or `false`. The reference is the variable's stable identity,
/// so renaming a variable keeps the binding; nothing is matched by name.
struct CanonicalTextBinding: Codable, Equatable, Sendable {
    static let key = CanonicalPageState.namespace + "text"
    static let maximumEncodedBytes = 1_024
    static let unsupportedReason = "Only text objects can show a page variable's value."
    static let missingVariableReason = "Choose a variable this page has. Add page variables on the page background."
    static let missingStatus = "This page has no such variable (it was removed, or the text was copied from another page), so the website shows the text's own content. Choose a variable or turn this off."
    var variable: UUID

    static func properties(_ binding: Self) -> [String: PropertyValue] {
        guard let text = CanonicalPageState.encode(binding) else { return [:] }
        return [key: .string(text)]
    }

    /// Exact key, bounded canonical text, on a Text that is not a form field.
    static func resolve(_ node: DocumentNode) throws -> Self? {
        guard let property = node.insertionProperty(key) else { return nil }
        guard node.kind == .text, !node.properties.contains(where: { $0.key.rawValue.hasPrefix("form.field.v1.") }),
              case .string(let text) = property.value else { throw ModelValidationError.invalidRuntimeState }
        let data = Data(text.utf8)
        guard data.count <= maximumEncodedBytes,
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any], Set(raw.keys) == ["variable"],
              let value = try? JSONDecoder().decode(Self.self, from: data), CanonicalPageState.encode(value) == text else {
            throw ModelValidationError.invalidRuntimeState
        }
        return value
    }

    /// What the website shows for a value; the runtime writes the same text.
    static func displayText(_ value: CanonicalVariableValue) -> String { value.text }

    /// SF-1106-003/004: the Inspector's explanation of what the website shows and why.
    static func status(_ binding: Self, variables: [CanonicalStateVariable]) -> String {
        guard let variable = variables.first(where: { $0.id == binding.variable }) else { return missingStatus }
        return "On the website this text shows \(variable.name) (\(variable.type.label)), starting as \u{201C}\(displayText(variable.initial))\u{201D}, in every language. The canvas keeps the text's own content, which the website shows if the variable is removed."
    }

    /// The page as the website writes it: every bound Text whose variable the
    /// page has shows that variable's starting value. The build calls this after
    /// translations and collection items have filled the page, so the variable
    /// wins over both; an unresolved binding keeps the page's own text.
    static func outputPage(_ page: DocumentPage) -> DocumentPage {
        let variables = Dictionary(CanonicalPageState.variables(on: page).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard !variables.isEmpty else { return page }
        var result = page
        for index in result.nodes.indices {
            guard let binding = try? resolve(result.nodes[index]), let variable = variables[binding.variable] else { continue }
            let text = PropertyValue.string(displayText(variable.initial))
            if let property = result.nodes[index].properties.firstIndex(where: { $0.key.rawValue == CollectionTemplates.textKey }) {
                result.nodes[index].properties[property].value = text
            } else {
                result.nodes[index].properties.append(NodeProperty(key: PropertyKey(rawValue: CollectionTemplates.textKey), value: text))
            }
        }
        return result
    }
}

/// OD-039 / SF-1105 (ADR-0062, ADR-0065): an overlay starts hidden on the
/// website and opens through an Open Overlay action. A modal keeps focus
/// inside, has a backdrop and is centred; a popover or menu opens where it is
/// drawn or, with a placement, next to the object whose interaction opens it;
/// a menu closes after one of its links or buttons is used and arrow keys move
/// through it. Escape always closes the top one.
struct CanonicalOverlay: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case modal, popover, menu
        var label: String {
            switch self {
            case .modal: "Modal Dialog"
            case .popover: "Popover"
            case .menu: "Menu"
            }
        }
    }
    /// SF-1105-002: the side of the trigger a popover or menu opens on. The
    /// website moves it to the opposite side when it does not fit. Start and
    /// end follow the reading direction. Omitted means where it is drawn.
    enum Placement: String, CaseIterable, Sendable {
        case below, above, start, end
        var label: String {
            switch self {
            case .below: "Below the Trigger"
            case .above: "Above the Trigger"
            case .start: "Before the Trigger"
            case .end: "After the Trigger"
            }
        }
    }
    static let prefix = "overlay."
    static let namespace = "overlay.v1."
    static let kindKey = namespace + "kind"
    static let dismissKey = namespace + "dismissOutside"
    /// Optional; only stored for a popover or menu.
    static let placementKey = namespace + "placement"
    static let supportedKinds: Set<NodeKind> = [.frame, .section, .stack, .grid]
    static let defaults = Self(kind: .modal, dismissesOnOutsideClick: true)
    static let unsupportedReason = "Overlays are frames, sections, stacks or grids."
    var kind: Kind
    var dismissesOnOutsideClick: Bool
    var placement: Placement? = nil
    /// A modal is always centred, so its placement is never written.
    var properties: [String: PropertyValue] {
        var values: [String: PropertyValue] = [Self.kindKey: .string(kind.rawValue), Self.dismissKey: .boolean(dismissesOnOutsideClick)]
        if let placement, kind != .modal { values[Self.placementKey] = .string(placement.rawValue) }
        return values
    }
    static func resolve(_ node: DocumentNode) throws -> Self? {
        let owned = node.properties.filter { $0.key.rawValue.hasPrefix(prefix) }
        guard !owned.isEmpty else { return nil }
        let keys = Set(owned.map(\.key.rawValue))
        guard supportedKinds.contains(node.kind), owned.count == keys.count,
              keys == [kindKey, dismissKey] || keys == [kindKey, dismissKey, placementKey],
              let kind = node.insertionStringProperty(kindKey).flatMap(Kind.init(rawValue:)),
              case .boolean(let dismiss)? = node.insertionProperty(dismissKey)?.value else {
            throw ModelValidationError.invalidOverlayState
        }
        var result = Self(kind: kind, dismissesOnOutsideClick: dismiss)
        if keys.contains(placementKey) {
            guard kind != .modal, let placement = node.insertionStringProperty(placementKey).flatMap(Placement.init(rawValue:)) else {
                throw ModelValidationError.invalidOverlayState
            }
            result.placement = placement
        }
        return result
    }
}

enum EventGraphOutput {
    /// Start-hidden nodes use the `hidden` attribute in the initial HTML, so the
    /// first render already matches the runtime state. Every page that runs
    /// the runtime needs this rule too: static layout gives each object an
    /// explicit `display`, which would otherwise win over `hidden`.
    static let hiddenCSS = "[data-siteforge-node][hidden] { display:none !important; }"
    /// SF-1105: one complete rule per line. Static Release minifies whole rules
    /// (ADR-0120), so a line's minified form appears unchanged in release CSS.
    /// A modal whose contents are written separately (`data-siteforge-flat`,
    /// ADR-0065) keeps its static position; the runtime centres it with them.
    static let overlayCSS = [
        "[data-siteforge-overlay=\"modal\"]:not([hidden]):not([data-siteforge-flat]) { position:fixed !important; left:50% !important; top:50% !important; right:auto !important; bottom:auto !important; transform:translate(-50%,-50%) !important; max-width:calc(100vw - 32px); max-height:calc(100vh - 32px); overflow:auto; }",
        ".sf-overlay-backdrop { position:fixed; inset:0; background:rgba(0,0,0,0.45); }",
    ].joined(separator: "\n")

    struct VariableOutput: Codable, Equatable, Sendable { let id: String; let type: String; let value: CanonicalVariableValue }
    struct ConditionOutput: Codable, Equatable, Sendable { let equals: CanonicalVariableValue; let variable: String }

    struct PageOutput: Equatable, Sendable {
        var configurations: [NodeID: String] = [:]
        var startsHidden: Set<NodeID> = []
        /// Extra attributes, already escaped: overlay kind and role, visibility conditions.
        var attributes: [NodeID: String] = [:]
        /// Page variables and their initial values, set when the runtime is needed.
        var stateJSON: String? = nil
        var hasOverlays = false
        /// ADR-0065: `data-siteforge-within` and `data-siteforge-flat` on static-layout pages.
        var memberAttributes: [NodeID: String] = [:]
        var needsRuntime: Bool { !configurations.isEmpty || !attributes.isEmpty }
        var isEmpty: Bool { configurations.isEmpty && startsHidden.isEmpty && attributes.isEmpty && memberAttributes.isEmpty }
        /// Everything written after an object's class and accessibility attributes.
        var htmlAttributes: [NodeID: String] { attributes.merging(memberAttributes) { $0 + $1 } }
    }

    static func overlayIDs(_ page: DocumentPage) -> Set<NodeID> {
        Set(page.nodes.filter { (try? CanonicalOverlay.resolve($0)) != nil }.map(\.id))
    }

    /// The compiled action, or nil when it cannot run on this page (missing
    /// target, page or variable, a value of the wrong type, or a non-overlay).
    static func compile(_ action: CanonicalInteraction.Action, nodeIDs: Set<NodeID>, overlayIDs: Set<NodeID>,
                        variables: [UUID: CanonicalStateVariable], route: (PageID) -> String?) -> EventOutputConfiguration.Action? {
        switch action.kind {
        case .navigate:
            guard let pageID = action.page, let href = route(pageID) else { return nil }
            return EventOutputConfiguration.Action(kind: action.kind.rawValue, href: href)
        case .setVariable:
            guard let id = action.variable, let variable = variables[id], let value = action.value, value.type == variable.type else { return nil }
            return EventOutputConfiguration.Action(kind: action.kind.rawValue, variable: id.uuidString.lowercased(), value: value)
        case .toggleVariable:
            guard let id = action.variable, variables[id]?.type == .boolean else { return nil }
            return EventOutputConfiguration.Action(kind: action.kind.rawValue, variable: id.uuidString.lowercased())
        case .openOverlay, .closeOverlay:
            guard let target = action.target, overlayIDs.contains(target) else { return nil }
            return EventOutputConfiguration.Action(kind: action.kind.rawValue, target: target.description)
        case .show, .hide, .toggle, .focus, .scrollTo:
            guard let target = action.target, nodeIDs.contains(target) else { return nil }
            return EventOutputConfiguration.Action(kind: action.kind.rawValue, target: target.description)
        }
    }

    /// Actions that cannot run are left out (and reported by `findings`).
    static func page(_ page: DocumentPage, staticRoutes: [PageID: String], prefix: String) throws -> PageOutput {
        var result = PageOutput()
        let nodeIDs = Set(page.nodes.map(\.id)), overlays = overlayIDs(page)
        let variableList = CanonicalPageState.variables(on: page)
        let variables = Dictionary(uniqueKeysWithValues: variableList.map { ($0.id, $0) })
        for node in page.nodes {
            let overlay = try CanonicalOverlay.resolve(node)
            if let overlay {
                result.hasOverlays = true
                result.startsHidden.insert(node.id)
                result.attributes[node.id, default: ""] += " data-siteforge-overlay=\"\(overlay.kind.rawValue)\" role=\"dialog\""
                    + (overlay.kind == .modal ? " aria-modal=\"true\"" : "") + (overlay.dismissesOnOutsideClick ? " data-siteforge-dismiss-outside" : "")
                if let placement = overlay.placement, overlay.kind != .modal {
                    result.attributes[node.id, default: ""] += " data-siteforge-placement=\"\(placement.rawValue)\""
                }
            }
            // An overlay opens and closes only through interactions, so a
            // condition on it is left out (and reported by `findings`).
            var isBound = false
            if overlay == nil, let condition = try CanonicalPageState.condition(node), let variable = variables[condition.variable],
               variable.type == condition.equals.type,
               let json = CanonicalPageState.encode(ConditionOutput(equals: condition.equals, variable: condition.variable.uuidString.lowercased())) {
                result.attributes[node.id, default: ""] += " data-siteforge-visible-when=\"\(SafeHTMLEmitter.escape(json))\""
                // The runtime applies bindings on load, so the condition (not
                // Start hidden) decides the first render.
                isBound = true
                if variable.initial != condition.equals { result.startsHidden.insert(node.id) }
            }
            // C6 (ADR-0066): the build already wrote the starting value as the text
            // (`CanonicalTextBinding.outputPage`); the runtime updates it and its live
            // region announces the change. A binding the page cannot resolve is left out.
            if let binding = try CanonicalTextBinding.resolve(node), variables[binding.variable] != nil {
                result.attributes[node.id, default: ""] += " data-siteforge-text-variable=\"\(binding.variable.uuidString.lowercased())\" aria-live=\"polite\" aria-atomic=\"true\""
            }
            guard let graph = try CanonicalEventGraph.resolve(node) else { continue }
            if graph.startsHidden, !isBound { result.startsHidden.insert(node.id) }
            let interactions = graph.interactions.compactMap { interaction -> EventOutputConfiguration? in
                let actions = interaction.actions.compactMap {
                    compile($0, nodeIDs: nodeIDs, overlayIDs: overlays, variables: variables, route: { staticRoutes[$0].map { prefix + $0 } })
                }
                return actions.isEmpty ? nil : EventOutputConfiguration(trigger: interaction.trigger.rawValue, actions: actions)
            }
            if !interactions.isEmpty { result.configurations[node.id] = EventOutputConfiguration.json(interactions) }
            // C7 (ADR-0066): key presses need keyboard focus; buttons and links have it already.
            if !CanonicalEventGraph.clickKinds.contains(node.kind), graph.interactions.contains(where: { $0.trigger.keyboardKey != nil }) {
                result.attributes[node.id, default: ""] += " tabindex=\"0\""
            }
        }
        result.memberAttributes = try FlatContainerOutput.attributes(page)
        if result.needsRuntime, !variableList.isEmpty {
            result.stateJSON = CanonicalPageState.encode(variableList.map {
                VariableOutput(id: $0.id.uuidString.lowercased(), type: $0.type.rawValue, value: $0.initial)
            })
        }
        return result
    }

    /// SF-1101-003/004/006, SF-1105-003/004/006, SF-1106-003/004: actions that
    /// cannot run, pointer-only interactions, focus loops, invalid visibility
    /// conditions, and overlays that never open, have no accessible name or
    /// carry an ignored condition. Containers on static-layout pages need no
    /// finding: `FlatContainerOutput` keeps their contents with them.
    /// Findings name node identifiers only, never content.
    static func findings(_ page: DocumentPage, availablePageIDs: Set<PageID>) -> [StaticBuildFinding] {
        var output: [StaticBuildFinding] = []
        let nodeIDs = Set(page.nodes.map(\.id)), overlays = overlayIDs(page)
        let variables = Dictionary(uniqueKeysWithValues: CanonicalPageState.variables(on: page).map { ($0.id, $0) })
        var focusEdges: [NodeID: Set<NodeID>] = [:]
        var opened = Set<NodeID>()
        let ordered = page.nodes.sorted(by: { $0.id.description < $1.id.description })
        for node in ordered {
            if let condition = (try? CanonicalPageState.condition(node)) ?? nil,
               variables[condition.variable]?.type != condition.equals.type {
                output.append(StaticBuildFinding(severity: .warning, code: "state-binding-invalid", requirementID: "SF-1106-004",
                    affectedNodeID: node.id, explanation: "The visibility condition uses a variable that was removed or has another type; the object is always shown.",
                    repair: "Choose an existing variable and a value of its type, or remove the condition."))
            }
            if let binding = (try? CanonicalTextBinding.resolve(node)) ?? nil, variables[binding.variable] == nil {
                output.append(StaticBuildFinding(severity: .warning, code: "state-text-binding-missing", requirementID: "SF-1106-004",
                    affectedNodeID: node.id, explanation: "The text shows a page variable this page does not have (it was removed, or the text was copied from another page); the website shows the text's own content instead.",
                    repair: "Choose a variable of this page for the text, or turn off Show a variable's value."))
            }
            guard let graph = (try? CanonicalEventGraph.resolve(node)) ?? nil else { continue }
            let actions = graph.interactions.flatMap(\.actions)
            for action in actions {
                guard let target = action.target else { continue }
                // Show and Show or Hide open an overlay as well (the runtime keeps it on the overlay stack).
                if [.openOverlay, .show, .toggle].contains(action.kind) { opened.insert(target) }
            }
            let missing = actions.filter {
                compile($0, nodeIDs: nodeIDs, overlayIDs: overlays, variables: variables,
                        route: { availablePageIDs.contains($0) ? "" : nil }) == nil
            }.count
            if missing > 0 {
                output.append(StaticBuildFinding(severity: .warning, code: "interaction-target-missing", requirementID: "SF-1101-004",
                    affectedNodeID: node.id,
                    explanation: "\(missing) interaction action\(missing == 1 ? " points" : "s point") at an object, overlay, page or variable that is not available, or sets a value of the wrong type; the website leaves \(missing == 1 ? "it" : "them") out.",
                    repair: "Choose a new target, page or variable, or remove the action."))
            }
            let unreachable = graph.interactions.reduce(0) { (sum: Int, interaction: CanonicalInteraction) -> Int in
                guard let index = interaction.actions.firstIndex(where: { action in
                    action.kind == .navigate && (action.page.map { availablePageIDs.contains($0) } ?? false)
                }) else { return sum }
                return sum + interaction.actions.count - index - 1
            }
            if unreachable > 0 {
                output.append(StaticBuildFinding(severity: .warning, code: "interaction-action-unreachable", requirementID: "SF-1101-003",
                    affectedNodeID: node.id,
                    explanation: "\(unreachable) action\(unreachable == 1 ? " comes" : "s come") after Go To Page in the same interaction and never \(unreachable == 1 ? "runs" : "run").",
                    repair: "Move Go To Page to the end of the interaction, or remove the actions after it."))
            }
            let triggers = Set(graph.interactions.map(\.trigger))
            let pointer: Set<CanonicalInteraction.Trigger> = [.pointerEnter, .pointerLeave]
            let keyboard = Set(CanonicalInteraction.Trigger.allCases.filter { $0.keyboardKey != nil }).union([.focusIn, .focusOut, .click])
            if !triggers.isDisjoint(with: pointer), triggers.isDisjoint(with: keyboard) {
                output.append(StaticBuildFinding(severity: .warning, code: "interaction-pointer-only", requirementID: "SF-1101-006",
                    affectedNodeID: node.id, explanation: "Pointer Enters or Pointer Leaves interactions have no keyboard equivalent.",
                    repair: "Add the same actions for Focus In or Focus Out, or use a button with a Click interaction."))
            }
            if !CanonicalEventGraph.clickKinds.contains(node.kind), triggers.contains(where: { $0.keyboardKey != nil }) {
                output.append(StaticBuildFinding(severity: .warning, code: "interaction-key-focus-added", requirementID: "SF-1101-006",
                    affectedNodeID: node.id, explanation: "Key-press interactions run only while their object has keyboard focus, so the website adds this object to the Tab order.",
                    repair: "Use a button or link for key-press interactions, or give this object an Accessible name so screen readers announce it."))
            }
            for interaction in graph.interactions where interaction.trigger == .focusIn {
                for action in interaction.actions where action.kind == .focus {
                    if let target = action.target { focusEdges[node.id, default: []].insert(target) }
                }
            }
        }
        let looping = loopMembers(focusEdges)
        for start in focusEdges.keys.sorted(by: { $0.description < $1.description }) where looping.contains(start) {
            output.append(StaticBuildFinding(severity: .warning, code: "interaction-focus-loop", requirementID: "SF-1101-003",
                affectedNodeID: start, explanation: "Focus In interactions move focus in a loop; the website stops the chain after four steps.",
                repair: "Remove one Move Focus To action from the loop."))
        }
        for node in ordered where overlays.contains(node.id) {
            if !opened.contains(node.id) {
                output.append(StaticBuildFinding(severity: .warning, code: "overlay-unreachable", requirementID: "SF-1105-004",
                    affectedNodeID: node.id, explanation: "No interaction on this page opens this overlay, so it never appears on the website.",
                    repair: "Add an Open Overlay action to a button or link, or turn the overlay off."))
            }
            if CanonicalAccessibilityMetadata.value(.name, for: node).0 == nil {
                output.append(StaticBuildFinding(severity: .warning, code: "overlay-unnamed", requirementID: "SF-1105-006",
                    affectedNodeID: node.id, explanation: "The overlay has no accessible name, so screen readers announce it only as a dialog.",
                    repair: "Add an Accessible name to the overlay in the Accessibility section."))
            }
            if node.insertionProperty(CanonicalPageState.visibleWhenKey) != nil {
                output.append(StaticBuildFinding(severity: .warning, code: "overlay-condition-ignored", requirementID: "SF-1105-003",
                    affectedNodeID: node.id, explanation: "An overlay opens and closes only through interactions, so its visibility condition is ignored on the website.",
                    repair: "Remove the visibility condition, or set the variable and open the overlay in the same interaction."))
            }
        }
        return output
    }

    /// Objects on a Focus In / Move Focus To loop, that is members of a cycle.
    /// Iterative Tarjan: linear in objects and edges, so a long chain on a large
    /// page stays fast (lane C 007, ADR-0066); a search from every object was quadratic.
    private static func loopMembers(_ edges: [NodeID: Set<NodeID>]) -> Set<NodeID> {
        let ordered = edges.mapValues { $0.sorted { $0.description < $1.description } }
        var index: [NodeID: Int] = [:], low: [NodeID: Int] = [:], onStack = Set<NodeID>()
        var stack: [NodeID] = [], result = Set<NodeID>(), counter = 0
        for start in edges.keys.sorted(by: { $0.description < $1.description }) where index[start] == nil {
            var work: [(node: NodeID, next: Int)] = []
            func enter(_ node: NodeID) {
                index[node] = counter; low[node] = counter; counter += 1
                stack.append(node); onStack.insert(node); work.append((node, 0))
            }
            enter(start)
            while let (node, next) = work.last {
                let targets = ordered[node] ?? []
                if next < targets.count {
                    work[work.count - 1].next = next + 1
                    let target = targets[next]
                    if index[target] == nil { enter(target) }
                    else if onStack.contains(target), let order = index[target] { low[node] = min(low[node] ?? order, order) }
                    continue
                }
                work.removeLast()
                if let parent = work.last?.node, let value = low[node] { low[parent] = min(low[parent] ?? value, value) }
                guard low[node] == index[node] else { continue }
                var component: [NodeID] = []
                while let member = stack.popLast() {
                    onStack.remove(member); component.append(member)
                    if member == node { break }
                }
                if component.count > 1 || ordered[node]?.contains(node) == true { result.formUnion(component) }
            }
        }
        return result
    }
}

/// C7 (SF-1101-002/003, ADR-0066): one row of the page interactions overview.
struct PageInteractionSummary: Equatable, Sendable, Identifiable {
    /// The trigger object and the interaction's position on it. Instances of
    /// one component share interaction identities, so those are not used.
    let id: String
    let nodeID: NodeID
    let objectName: String
    let trigger: CanonicalInteraction.Trigger
    let actions: [String]
    /// Actions the website leaves out: a missing target, page or variable, or a value of the wrong type.
    let unavailableActions: Int
    var accessibilityLabel: String {
        "\(objectName), \(trigger.label): \(actions.joined(separator: ", "))"
            + (unavailableActions == 0 ? "" : ". \(unavailableActions) action\(unavailableActions == 1 ? "" : "s") cannot run")
    }
}

/// Every trigger and its actions on one page, in Layers order, described with
/// the names authors see. Read-only: choosing a row only selects its object.
enum PageInteractionOverview {
    static func summaries(_ page: DocumentPage, websitePages: [DocumentPage]) -> [PageInteractionSummary] {
        let names = Dictionary(page.nodes.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let pageNames = Dictionary(websitePages.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let variables = Dictionary(CanonicalPageState.variables(on: page).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let nodeIDs = Set(page.nodes.map(\.id)), overlays = EventGraphOutput.overlayIDs(page)
        var result: [PageInteractionSummary] = []
        for node in page.canonicalDepthFirstNodes() {
            guard let graph = try? CanonicalEventGraph.resolve(node) else { continue }
            for (index, interaction) in graph.interactions.enumerated() {
                let unavailable = interaction.actions.filter {
                    EventGraphOutput.compile($0, nodeIDs: nodeIDs, overlayIDs: overlays, variables: variables,
                                             route: { pageNames[$0] == nil ? nil : "" }) == nil
                }.count
                result.append(PageInteractionSummary(id: node.id.description + "/\(index)", nodeID: node.id, objectName: node.name,
                    trigger: interaction.trigger,
                    actions: interaction.actions.map { describe($0, names: names, pageNames: pageNames, variables: variables) },
                    unavailableActions: unavailable))
            }
        }
        return result
    }

    static func describe(_ action: CanonicalInteraction.Action, names: [NodeID: String], pageNames: [PageID: String],
                         variables: [UUID: CanonicalStateVariable]) -> String {
        switch action.kind {
        case .navigate:
            return action.kind.label + " " + (action.page.flatMap { pageNames[$0] } ?? "(missing page)")
        case .setVariable:
            let name = action.variable.flatMap { variables[$0]?.name } ?? "(missing variable)"
            return "Set \(name) to " + (action.value.map { CanonicalTextBinding.displayText($0) } ?? "")
        case .toggleVariable:
            return "Flip " + (action.variable.flatMap { variables[$0]?.name } ?? "(missing variable)")
        case .show, .hide, .toggle, .focus, .scrollTo, .openOverlay, .closeOverlay:
            return action.kind.label + " " + (action.target.flatMap { names[$0] } ?? "(missing object)")
        }
    }
}

/// SF-1101-004, SF-1104-004, SF-1105-004 (ADR-0065): without page flow or
/// automatic sizing, static layout writes every object as its own absolutely
/// placed element, so a container's contents are not inside its HTML element.
/// Each content element names the containers that the website hides, shows,
/// opens or reveals on scroll (`data-siteforge-within`, outermost first), and
/// an overlay with contents is marked `data-siteforge-flat`. Contents follow
/// their container in paint order, so one sibling rule per container hides
/// them with it without scripts; its reveal plays on them too, and both
/// runtimes treat them as part of the container.
enum FlatContainerOutput {
    struct Groups: Equatable, Sendable {
        var visibility: Set<NodeID> = []
        var entrances: [NodeID: CanonicalMotion.Entrance] = [:]
        var all: Set<NodeID> { visibility.union(entrances.keys) }
    }

    /// Containers with contents whose visibility the website changes, and
    /// those that reveal on scroll. Pages with page flow nest contents in HTML.
    static func groups(_ page: DocumentPage) throws -> Groups {
        guard !page.usesConnectedOutput else { return Groups() }
        let containers = Set(page.nodes.filter { !$0.childIDs.isEmpty }.map(\.id))
        let changesVisibility: Set<CanonicalInteraction.ActionKind> = [.show, .hide, .toggle, .openOverlay, .closeOverlay]
        var result = Groups(visibility: EventGraphOutput.overlayIDs(page).intersection(containers))
        for node in page.nodes {
            if containers.contains(node.id) {
                if node.insertionProperty(CanonicalPageState.visibleWhenKey) != nil { result.visibility.insert(node.id) }
                if let entrance = try CanonicalMotion.resolve(node)?.entrance { result.entrances[node.id] = entrance }
            }
            guard let graph = try CanonicalEventGraph.resolve(node) else { continue }
            if graph.startsHidden, containers.contains(node.id) { result.visibility.insert(node.id) }
            for action in graph.interactions.flatMap(\.actions) where changesVisibility.contains(action.kind) {
                if let target = action.target, containers.contains(target) { result.visibility.insert(target) }
            }
        }
        return result
    }

    /// The grouping ancestors of every element written on its own, outermost first.
    static func members(_ page: DocumentPage, groups: Set<NodeID>) -> [NodeID: [NodeID]] {
        guard !groups.isEmpty else { return [:] }
        let byID = Dictionary(page.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [NodeID: [NodeID]] = [:]
        // Form fields are written inside their form, which carries the attribute.
        for node in page.nodes where !node.properties.contains(where: { $0.key.rawValue.hasPrefix("form.field.v1.") }) {
            var ancestors: [NodeID] = [], parent = node.parent, seen: Set<NodeID> = [node.id]
            while case .node(let id) = parent, seen.insert(id).inserted, let ancestor = byID[id] {
                if groups.contains(id) { ancestors.insert(id, at: 0) }
                parent = ancestor.parent
            }
            if !ancestors.isEmpty { result[node.id] = ancestors }
        }
        return result
    }

    /// `data-siteforge-within` on contents and `data-siteforge-flat` on an overlay with contents.
    static func attributes(_ page: DocumentPage) throws -> [NodeID: String] {
        let found = try groups(page)
        var result = members(page, groups: found.all).mapValues { ids in
            " data-siteforge-within=\"" + ids.map(\.description).joined(separator: " ") + "\""
        }
        for id in EventGraphOutput.overlayIDs(page).intersection(found.visibility) { result[id, default: ""] += " data-siteforge-flat" }
        return result
    }

    /// One complete rule per line (static release minifies whole rules, ADR-0120).
    static func css(_ pages: [DocumentPage]) throws -> String {
        var lines: [String] = []
        for page in pages {
            let found = try groups(page)
            for id in found.visibility.sorted(by: { $0.description < $1.description }) {
                let name = id.description
                lines.append("[data-siteforge-node=\"\(name)\"][hidden] ~ [data-siteforge-within~=\"\(name)\"] { display:none !important; }")
            }
            for id in found.entrances.keys.sorted(by: { $0.description < $1.description }) {
                guard let entrance = found.entrances[id] else { continue }
                let name = id.description, member = "[data-siteforge-within~=\"\(name)\"]"
                lines.append("@media screen and (prefers-reduced-motion:no-preference) { .sf-motion-ready \(member):not(.sf-motion-entered) { opacity:0; } }")
                lines.append("@media screen and (prefers-reduced-motion:no-preference) { .sf-motion-ready \(member).sf-motion-entered { animation:sf-entrance-\(name) \(Int(entrance.milliseconds))ms \(entrance.easing.rawValue) \(Int(entrance.delayMilliseconds))ms both; } }")
            }
        }
        return lines.joined(separator: "\n")
    }
}

enum EventGraphRuntime {
    static let javascript = #"""
/* SiteForge interaction runtime (OD-039). It runs only SiteForge's fixed actions from validated build data. */
(() => {
  'use strict';
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  const identifier = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
  const kinds = new Set(['show', 'hide', 'toggle', 'focus', 'scroll-to', 'navigate', 'set-variable', 'toggle-variable', 'open-overlay', 'close-overlay']);
  const events = {'click': 'click', 'pointer-enter': 'pointerenter', 'pointer-leave': 'pointerleave', 'focus-in': 'focusin', 'focus-out': 'focusout'};
  // C7 (ADR-0066): key-press interactions run while their own object has keyboard focus.
  const keys = {'key-enter': 'Enter', 'key-escape': 'Escape', 'key-arrow-up': 'ArrowUp', 'key-arrow-down': 'ArrowDown', 'key-arrow-left': 'ArrowLeft', 'key-arrow-right': 'ArrowRight'};
  const focusable = 'a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])';
  const find = id => typeof id === 'string' && identifier.test(id) ? document.querySelector('[data-siteforge-node="' + id + '"]') : null;
  const read = (element, name) => { try { return JSON.parse(element.getAttribute(name)); } catch { return null; } };
  const typeOf = value => typeof value === 'boolean' || typeof value === 'string' ? typeof value : Number.isInteger(value) ? 'number' : '';

  // SF-1106: page variables. The build fixed each type; a write of another type is ignored.
  const variables = new Map();
  const state = document.querySelector('[data-siteforge-state]');
  const list = state ? read(state, 'data-siteforge-state') : null;
  if (Array.isArray(list)) for (const item of list.slice(0, 16)) {
    if (item && identifier.test(item.id) && typeOf(item.value) === item.type) variables.set(item.id, {type: item.type, value: item.value});
  }
  const bindings = [];
  for (const element of document.querySelectorAll('[data-siteforge-visible-when]')) {
    const rule = read(element, 'data-siteforge-visible-when');
    if (rule && variables.has(rule.variable)) bindings.push([element, rule]);
  }
  // SF-1106 (C6, ADR-0066): text bound to a variable. The build already wrote the starting value, so the page
  // reads the same without scripts; the text follows the variable and its live region announces the change.
  const texts = [];
  for (const element of document.querySelectorAll('[data-siteforge-text-variable]')) {
    const id = element.getAttribute('data-siteforge-text-variable');
    if (variables.has(id)) texts.push([element.querySelector('[data-siteforge-text]') || element, id]);
  }
  const shown = value => typeof value === 'boolean' ? (value ? 'true' : 'false') : String(value);
  const render = () => {
    for (const [element, rule] of bindings) element.hidden = variables.get(rule.variable).value !== rule.equals;
    for (const [element, id] of texts) {
      const text = shown(variables.get(id).value);
      if (element.textContent !== text) element.textContent = text;
    }
  };
  function write(id, value) {
    const variable = variables.get(id);
    if (!variable || typeOf(value) !== variable.type || variable.value === value) return;
    variable.value = value;
    render();
  }

  // SF-1105: overlays. The newest open overlay is on top; closing one also closes those opened after it.
  const stack = [];
  const top = () => stack[stack.length - 1];
  // Buttons and links that open, show or hide something say whether it is open (ADR-0066).
  const expand = (opener, value) => { if (opener && (opener.tagName === 'BUTTON' || opener.tagName === 'A')) opener.setAttribute('aria-expanded', String(value)); };
  // ADR-0065: on a page without page flow a container's contents are separate elements that name it
  // (`data-siteforge-within`); they count as part of the overlay for focus, outside clicks and placement.
  const groupOf = element => {
    const id = element.getAttribute('data-siteforge-node') || '';
    const members = identifier.test(id) ? document.querySelectorAll('[data-siteforge-within~="' + id + '"]') : [];
    return [element].concat(Array.from(members));
  };
  const holds = (element, node) => !!node && groupOf(element).some(part => part.contains(node));
  const focusables = element => groupOf(element)
    .flatMap(part => (part.matches(focusable) ? [part] : []).concat(Array.from(part.querySelectorAll(focusable))))
    .filter(item => !item.closest('[hidden]') && item.getClientRects().length > 0);
  // SF-1105-002: a popover or menu with a placement opens next to its trigger and moves to the other side
  // when it does not fit; a modal whose contents are separate elements is centred the same way. `translate`
  // moves the overlay and its contents together without changing the page layout.
  const gap = 8, margin = 8;
  function place(entry) {
    const side = entry.modal ? (entry.flat ? 'center' : '') : (entry.element.getAttribute('data-siteforge-placement') || '');
    if (!side || (side !== 'center' && !(entry.anchor && entry.anchor.isConnected))) return;
    const group = groupOf(entry.element);
    for (const part of group) part.style.translate = '';
    const rects = group.map(part => part.getBoundingClientRect()).filter(rect => rect.width > 0 || rect.height > 0);
    if (!rects.length) return;
    const minX = Math.min(...rects.map(rect => rect.left)), minY = Math.min(...rects.map(rect => rect.top));
    const width = Math.max(...rects.map(rect => rect.right)) - minX, height = Math.max(...rects.map(rect => rect.bottom)) - minY;
    let x = (innerWidth - width) / 2, y = (innerHeight - height) / 2;
    if (side !== 'center') {
      const trigger = entry.anchor.getBoundingClientRect();
      const rtl = getComputedStyle(entry.anchor).direction === 'rtl';
      if (side === 'below' || side === 'above') {
        const below = trigger.bottom + gap, above = trigger.top - gap - height;
        const fitsBelow = below + height <= innerHeight - margin, fitsAbove = above >= margin;
        y = side === 'below' ? (fitsBelow || !fitsAbove ? below : above) : (fitsAbove || !fitsBelow ? above : below);
        x = rtl ? trigger.right - width : trigger.left;
      } else {
        const right = trigger.right + gap, left = trigger.left - gap - width;
        const fitsRight = right + width <= innerWidth - margin, fitsLeft = left >= margin;
        // Start and end follow the reading direction.
        const prefersRight = (side === 'end') !== rtl;
        x = prefersRight ? (fitsRight || !fitsLeft ? right : left) : (fitsLeft || !fitsRight ? left : right);
        y = trigger.top;
      }
    }
    x = Math.max(margin, Math.min(x, innerWidth - margin - width));
    y = Math.max(margin, Math.min(y, innerHeight - margin - height));
    const shift = Math.round(x - minX) + 'px ' + Math.round(y - minY) + 'px';
    for (const part of group) part.style.translate = shift;
  }
  let placing = 0;
  const placeAll = () => { placing = 0; for (const entry of stack) place(entry); };
  const reposition = () => { if (!placing) placing = requestAnimationFrame(placeAll); };
  addEventListener('resize', reposition, {passive: true});
  addEventListener('scroll', reposition, {passive: true});
  function open(element, opener, anchor) {
    if (!element.hasAttribute('data-siteforge-overlay')) return;
    const current = stack.find(entry => entry.element === element);
    if (current) { if (current.opener === opener) close(element); return; }
    const modal = element.getAttribute('data-siteforge-overlay') === 'modal';
    const entry = {element, opener, anchor, modal, flat: element.hasAttribute('data-siteforge-flat'), backdrop: null, home: null};
    const layer = 1000 + stack.length * 2;
    if (modal) {
      entry.backdrop = document.createElement('div');
      entry.backdrop.className = 'sf-overlay-backdrop';
      entry.backdrop.setAttribute('aria-hidden', 'true');
      entry.backdrop.style.zIndex = String(layer);
      entry.backdrop.addEventListener('click', () => { if (element.hasAttribute('data-siteforge-dismiss-outside')) close(element); });
      document.body.appendChild(entry.backdrop);
    }
    if (modal && !entry.flat) {
      // SF-1105 portal: an open modal lives at the end of <body>, so an ancestor's transform,
      // filter, isolation or entrance animation cannot move it or put it under its backdrop.
      // A modal whose contents are separate elements already sits directly in <body>.
      entry.home = document.createComment('siteforge-overlay');
      element.before(entry.home);
      document.body.appendChild(element);
    }
    for (const part of groupOf(element)) part.style.zIndex = String(layer + 1);
    element.hidden = false;
    stack.push(entry);
    place(entry);
    expand(opener, true);
    const first = focusables(element)[0];
    if (!first && !element.hasAttribute('tabindex')) element.setAttribute('tabindex', '-1');
    (first || element).focus();
  }
  function close(element) {
    const index = stack.findIndex(entry => entry.element === element);
    if (index < 0) return;
    const closing = stack.splice(index);
    const restore = closing[0].opener;
    for (const entry of closing.reverse()) {
      entry.element.hidden = true;
      for (const part of groupOf(entry.element)) { part.style.zIndex = ''; part.style.translate = ''; }
      if (entry.backdrop) entry.backdrop.remove();
      if (entry.home) entry.home.replaceWith(entry.element);
      expand(entry.opener, false);
    }
    if (restore && restore.isConnected && typeof restore.focus === 'function') restore.focus();
  }
  document.addEventListener('keydown', event => {
    const entry = top();
    if (!entry) return;
    if (event.key === 'Escape') { event.preventDefault(); close(entry.element); return; }
    // SF-1105-006: in a menu, arrow keys, Home and End move between its links and buttons.
    // A key-press interaction inside the menu that handled the key itself (preventDefault) wins.
    if (entry.element.getAttribute('data-siteforge-overlay') === 'menu' && !event.defaultPrevented && ['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)
        && (holds(entry.element, document.activeElement) || document.activeElement === entry.opener)) {
      const choices = focusables(entry.element);
      if (!choices.length) return;
      const current = choices.indexOf(document.activeElement);
      const next = event.key === 'Home' ? 0 : event.key === 'End' ? choices.length - 1
        : event.key === 'ArrowDown' ? (current + 1) % choices.length : (current <= 0 ? choices.length - 1 : current - 1);
      event.preventDefault();
      choices[next].focus();
      return;
    }
    if (event.key !== 'Tab' || !entry.modal) return;
    const items = focusables(entry.element);
    if (!items.length) { event.preventDefault(); entry.element.focus(); return; }
    const first = items[0], last = items[items.length - 1], inside = holds(entry.element, document.activeElement);
    if (event.shiftKey && (!inside || document.activeElement === first)) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && (!inside || document.activeElement === last)) { event.preventDefault(); first.focus(); }
  });
  // Focus that leaves a modal (for example after a click on the page) returns to it.
  document.addEventListener('focusin', event => {
    const entry = top();
    if (entry && entry.modal && !holds(entry.element, event.target)) (focusables(entry.element)[0] || entry.element).focus();
  });
  document.addEventListener('pointerdown', event => {
    const entry = top();
    if (!entry || entry.modal || !entry.element.hasAttribute('data-siteforge-dismiss-outside')) return;
    if (holds(entry.element, event.target) || (entry.opener && entry.opener.contains(event.target))) return;
    close(entry.element);
  }, true);
  // A menu closes after one of its links or buttons is used.
  document.addEventListener('click', event => {
    const entry = top();
    if (entry && entry.element.getAttribute('data-siteforge-overlay') === 'menu' && holds(entry.element, event.target)
        && event.target.closest('a[href],button')) close(entry.element);
  });

  // SF-1101-006 / SF-1105-006 (ADR-0066): a button or link that opens an overlay, or shows and hides an
  // object, says so before it is first used: aria-haspopup for an overlay and its starting aria-expanded.
  function describe(element, actions) {
    if (element.tagName !== 'BUTTON' && element.tagName !== 'A') return;
    for (const action of actions) {
      const target = action ? find(action.target) : null;
      if (!target || element.hasAttribute('aria-expanded')) continue;
      const overlay = target.hasAttribute('data-siteforge-overlay');
      if (action.kind === 'open-overlay' || (overlay && (action.kind === 'show' || action.kind === 'toggle'))) {
        element.setAttribute('aria-haspopup', 'dialog');
        element.setAttribute('aria-expanded', 'false');
      } else if (action.kind === 'toggle') element.setAttribute('aria-expanded', String(!target.hidden));
    }
  }

  let depth = 0;
  function run(source, actions) {
    if (depth >= 4) return; // Focus chains stop after four steps.
    depth++;
    try {
      for (const action of actions) {
        if (!action || !kinds.has(action.kind)) continue;
        if (action.kind === 'navigate') {
          const href = action.href;
          if (typeof href === 'string' && href && !/[:\\]/.test(href) && !href.startsWith('//')) location.assign(href);
          continue;
        }
        if (action.kind === 'set-variable') { write(action.variable, action.value); continue; }
        if (action.kind === 'toggle-variable') {
          const variable = variables.get(action.variable);
          if (variable && variable.type === 'boolean') write(action.variable, !variable.value);
          continue;
        }
        const target = find(action.target);
        if (!target) continue;
        // Show, Hide and Show or Hide on an overlay open or close it, so its stack, backdrop and focus stay right.
        const overlay = target.hasAttribute('data-siteforge-overlay');
        if (action.kind === 'open-overlay' || (overlay && target.hidden && (action.kind === 'show' || action.kind === 'toggle'))) open(target, source.matches(focusable) ? source : document.activeElement, source);
        else if (action.kind === 'close-overlay' || (overlay && !target.hidden && (action.kind === 'hide' || action.kind === 'toggle'))) close(target);
        else if (overlay && (action.kind === 'show' || action.kind === 'hide' || action.kind === 'toggle')) continue;
        else if (action.kind === 'show') target.hidden = false;
        else if (action.kind === 'hide') target.hidden = true;
        else if (action.kind === 'toggle') target.hidden = !target.hidden;
        else if (action.kind === 'scroll-to') target.scrollIntoView({behavior: reduce.matches ? 'auto' : 'smooth', block: 'start'});
        else if (action.kind === 'focus') {
          if (!target.matches('a[href],button,input,select,textarea,[tabindex]')) target.setAttribute('tabindex', '-1');
          target.focus();
        }
        if (action.kind === 'show' || action.kind === 'hide' || action.kind === 'toggle') expand(source, !target.hidden);
      }
    } finally { depth--; }
  }
  render();
  const entering = new Map();
  for (const element of document.querySelectorAll('[data-siteforge-events]')) {
    const config = read(element, 'data-siteforge-events');
    if (!Array.isArray(config)) continue;
    let hasUserInteraction = false;
    for (const item of config.slice(0, 8)) {
      if (!item || !Array.isArray(item.actions)) continue;
      const actions = item.actions.slice(0, 8);
      if (item.trigger === 'click' || Object.prototype.hasOwnProperty.call(keys, item.trigger)) describe(element, actions);
      if (item.trigger === 'page-load') run(element, actions);
      else if (item.trigger === 'viewport-enter') entering.set(element, (entering.get(element) || []).concat([actions]));
      else if (Object.prototype.hasOwnProperty.call(keys, item.trigger)) {
        hasUserInteraction = true;
        const key = keys[item.trigger];
        element.addEventListener('keydown', event => {
          // Only while the object itself has focus (not a control inside it), without modifiers or text composition.
          if (event.key !== key || event.target !== element || event.altKey || event.ctrlKey || event.metaKey || event.isComposing) return;
          if (key.startsWith('Arrow')) event.preventDefault(); // An arrow key would also scroll the page.
          run(element, actions);
        });
      }
      else if (Object.prototype.hasOwnProperty.call(events, item.trigger)) {
        hasUserInteraction = true;
        element.addEventListener(events[item.trigger], () => run(element, actions));
      }
    }
    // Untargeted action buttons are inert in static HTML. Enable a button
    // only after its compiled user interaction has been installed.
    if (hasUserInteraction && element.tagName === 'BUTTON' && element.type === 'button') {
      element.disabled = false;
      element.removeAttribute('aria-disabled');
    }
  }
  if (entering.size && typeof IntersectionObserver === 'function') {
    const observer = new IntersectionObserver(entries => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        observer.unobserve(entry.target);
        for (const actions of entering.get(entry.target) || []) run(entry.target, actions);
      }
    });
    for (const element of entering.keys()) observer.observe(element);
  }
  // Without IntersectionObserver, Scrolled Into View runs once at load so its actions still happen.
  else for (const [element, lists] of entering) for (const actions of lists) run(element, actions);
})();

"""#
}

enum DecorativeEffectRuntime {
    static let javascript = #"""
/* SiteForge local decorative runtime. Configuration is validated build data. */
(() => {
  'use strict';
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  const hover = matchMedia('(hover: hover) and (pointer: fine)');
  const active = new Set(), instances = new Map(), failed = new WeakSet();
  let frame = 0, disposed = false, suspended = false;
  const stats = {frames: 0, drawMilliseconds: 0, maximumDrawMilliseconds: 0};
  const vertex = 'attribute vec2 point;varying vec2 uv;void main(){uv=(point+1.0)*0.5;gl_Position=vec4(point,0.0,1.0);}';
  const fragment = `precision highp float;varying vec2 uv;uniform vec2 size;uniform vec2 pointer;
    uniform vec2 pull;uniform float radius;uniform vec2 direction;uniform sampler2D ramp;
    void main(){vec2 p=vec2(uv.x,1.0-uv.y)*size;vec2 d=p-pointer;
      float r=length(d)/radius;float influence=exp(-3.0*r*r)*(1.0-smoothstep(0.75,1.0,r));
      vec2 tangent=vec2(-d.y,d.x)/max(radius,1.0);
      p-=influence*(pull+tangent*(pull.x*d.y-pull.y*d.x)/max(radius,1.0)*0.35);
      float span=abs(direction.x)*size.x+abs(direction.y)*size.y;
      float t=clamp(dot(p-size*0.5,direction)/max(span,1.0)+0.5,0.0,1.0);
      gl_FragColor=texture2D(ramp,vec2(t,0.5));}`;
  const allowed = () => !disposed && !suspended && !document.hidden && !motion.matches && hover.matches;
  const request = item => {if (!allowed() || !item.visible || item.retired) return;
    active.add(item); if (!frame) frame=requestAnimationFrame(tick);};
  function tick(now) {
    frame=0;
    // Read every active element before changing any classes/canvas sizes.
    const measured=Array.from(active).map(item=>[item,item.measure()]);
    for (const [item,geometry] of measured) if (!item.draw(now,geometry)) active.delete(item);
    if (active.size && allowed()) frame=requestAnimationFrame(tick);
  }
  function shader(gl, type, source) {
    const value=gl.createShader(type);gl.shaderSource(value,source);gl.compileShader(value);
    if (!gl.getShaderParameter(value,gl.COMPILE_STATUS)) {gl.deleteShader(value);throw Error('Shader unavailable');}
    return value;
  }
  class Flow {
    constructor(element, config) {
      this.element=element;this.config=config;this.visible=true;this.retired=false;
      this.pointer=null;this.previous=null;this.input=null;this.pull=[0,0];this.last=0;this.lastMove=0;
      this.canvas=document.createElement('canvas');this.canvas.className='sf-flow-canvas';
      this.canvas.setAttribute('aria-hidden','true');this.canvas.hidden=true;
      this.shaders=[];
      try {
      const gl=this.gl=this.canvas.getContext('webgl',{alpha:true,antialias:false,premultipliedAlpha:true,depth:false,stencil:false,preserveDrawingBuffer:false});
      if (!gl) throw Error('WebGL unavailable');
      this.program=gl.createProgram();this.shaders.push(shader(gl,gl.VERTEX_SHADER,vertex));this.shaders.push(shader(gl,gl.FRAGMENT_SHADER,fragment));
      this.shaders.forEach(s=>gl.attachShader(this.program,s));gl.linkProgram(this.program);
      if (!gl.getProgramParameter(this.program,gl.LINK_STATUS)) throw Error('Program unavailable');
      gl.useProgram(this.program);
      this.buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);
      gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,-1,1,1,-1,1,1]),gl.STATIC_DRAW);
      const location=gl.getAttribLocation(this.program,'point');gl.enableVertexAttribArray(location);gl.vertexAttribPointer(location,2,gl.FLOAT,false,0,0);
      this.uniform={};for(const name of ['size','pointer','pull','radius','direction','ramp'])this.uniform[name]=gl.getUniformLocation(this.program,name);
      const ramp=document.createElement('canvas');ramp.width=1024;ramp.height=1;
      const context=ramp.getContext('2d'), pixels=context.createImageData(1024,1);
      // Explicit premultiplied sRGB interpolation, matching the authored CSS
      // gradient even when transparent endpoints have different RGB values.
      const stops=config.stops.map((s,i)=>({...s,index:i})).sort((a,b)=>a.position-b.position||a.index-b.index);
      for(let x=0;x<1024;x++){
        const t=x/1023;let right=stops.findIndex(s=>s.position>t),a,b;
        if(right===0){a=b=stops[0];}else if(right<0){a=b=stops[stops.length-1];}else{a=stops[right-1];b=stops[right];}
        const f=a===b?0:(t-a.position)/(b.position-a.position),alpha=a.alpha+(b.alpha-a.alpha)*f;
        for(const [i,key] of ['red','green','blue'].entries())pixels.data[x*4+i]=Math.round(255*(alpha>0?(a[key]*a.alpha*(1-f)+b[key]*b.alpha*f)/alpha:0));
        pixels.data[x*4+3]=Math.round(255*alpha);
      }
      context.putImageData(pixels,0,0);
      this.texture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,this.texture);gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL,true);
      gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,ramp);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
      this.move=event=>{this.input=[event.clientX,event.clientY];this.lastMove=performance.now();request(this);};
      this.leave=()=>{this.input=null;this.previous=null;request(this);};
      this.loss=event=>{event.preventDefault();failed.add(this.element);this.dispose();};
      element.addEventListener('pointermove',this.move,{passive:true});element.addEventListener('pointerleave',this.leave,{passive:true});
      element.addEventListener('pointercancel',this.leave,{passive:true});element.addEventListener('lostpointercapture',this.leave,{passive:true});this.canvas.addEventListener('webglcontextlost',this.loss);
      this.resize=new ResizeObserver(()=>{this.last=0;this.previous=null;request(this);});this.resize.observe(element);
      this.intersection=new IntersectionObserver(entries=>{this.visible=entries[0].isIntersecting;if(!this.visible)this.rest();});this.intersection.observe(element);
      if(getComputedStyle(element).position==='static')element.classList.add('sf-flow-host');
      element.prepend(this.canvas);
      }catch(error){this.dispose();throw error;}
    }
    measure(){const rect=this.element.getBoundingClientRect();return {rect,w:this.element.clientWidth,h:this.element.clientHeight};}
    draw(now,geometry) {
      if (!allowed() || !this.visible || !this.element.isConnected) {this.rest();return false;}
      const start=performance.now(),{rect,w,h}=geometry;
      if(w<1||h<1||rect.width<1||rect.height<1){this.rest();return false;}
      const dt=Math.min(.05,Math.max(.001,(now-(this.last||now-16))/1000));this.last=now;
      const c=this.config;
      let desired=[0,0];
      if(this.input){
        const point=[(this.input[0]-rect.left)*w/rect.width,(this.input[1]-rect.top)*h/rect.height];
        if(this.previous && now-this.lastMove<80){const dx=point[0]-this.previous[0],dy=point[1]-this.previous[1];
          const distance=Math.hypot(dx,dy),maximum=c.radius*c.strength*.45;
          const factor=distance>0?Math.min(maximum/distance,.12/dt):0;desired=[dx*factor,dy*factor];}
        this.pointer=this.pointer?this.pointer.map((p,i)=>p+(point[i]-p)*(1-Math.exp(-c.response*dt))):point;this.previous=point;
      }
      const response=Math.hypot(...desired)>0?c.response:1/c.returnSeconds;
      const blend=1-Math.exp(-response*dt);
      this.pull=this.pull.map((p,i)=>p+(desired[i]-p)*blend);
      if(Math.hypot(...this.pull)<.03 && now-this.lastMove>100){this.rest(false);return false;}
      const ratio=Math.min(1.25,devicePixelRatio||1,1024/w,768/h,Math.sqrt(786432/(w*h)));
      const width=Math.max(1,Math.round(w*ratio)),height=Math.max(1,Math.round(h*ratio));
      if(this.canvas.width!==width||this.canvas.height!==height){this.canvas.width=width;this.canvas.height=height;}
      const gl=this.gl;gl.useProgram(this.program);gl.viewport(0,0,width,height);
      gl.uniform2f(this.uniform.size,w,h);gl.uniform2fv(this.uniform.pointer,this.pointer||[w/2,h/2]);gl.uniform2fv(this.uniform.pull,this.pull);
      gl.uniform1f(this.uniform.radius,c.radius);const angle=c.angle*Math.PI/180;
      gl.uniform2f(this.uniform.direction,Math.cos(angle),Math.sin(angle));gl.uniform1i(this.uniform.ramp,0);
      gl.drawArrays(gl.TRIANGLES,0,6);
      this.canvas.hidden=false;this.element.classList.add('sf-flow-ready');
      const elapsed=performance.now()-start;stats.frames++;stats.drawMilliseconds+=elapsed;
      stats.maximumDrawMilliseconds=Math.max(stats.maximumDrawMilliseconds,elapsed);return true;
    }
    rest(clearInput=true){active.delete(this);this.canvas.hidden=true;this.element.classList.remove('sf-flow-ready');this.pull=[0,0];this.last=0;if(clearInput){this.previous=null;this.pointer=null;this.input=null;}}
    dispose(){if(this.retired)return;this.retired=true;this.rest();this.resize?.disconnect();this.intersection?.disconnect();
      for(const event of ['pointerleave','pointercancel','lostpointercapture'])this.element.removeEventListener(event,this.leave);
      this.element.removeEventListener('pointermove',this.move);this.canvas.removeEventListener('webglcontextlost',this.loss);
      if(this.gl){this.shaders.forEach(s=>this.gl.deleteShader(s));if(this.program)this.gl.deleteProgram(this.program);if(this.texture)this.gl.deleteTexture(this.texture);if(this.buffer)this.gl.deleteBuffer(this.buffer);}
      this.canvas.remove();this.element.classList.remove('sf-flow-host');instances.delete(this.element);}
  }
  function valid(config){return !!config && !(config.version!==1||![config.radius,config.strength,config.response,config.returnSeconds,config.angle].every(Number.isFinite)
    ||config.radius<24||config.radius>1200||config.strength<0||config.strength>1||config.response<.5||config.response>30
    ||config.returnSeconds<.1||config.returnSeconds>5||!Array.isArray(config.stops)||config.stops.length<2||config.stops.length>64
    ||!config.stops.every(s=>s&&[s.position,s.red,s.green,s.blue,s.alpha].every(v=>Number.isFinite(v)&&v>=0&&v<=1)));}
  function update(element,config){
    if(!(element instanceof Element)||!valid(config))return false;
    const item=instances.get(element);
    if(item && item.config.angle===config.angle && JSON.stringify(item.config.stops)===JSON.stringify(config.stops)){
      item.config=config;request(item);
    }else{item?.dispose();failed.delete(element);}
    element.setAttribute('data-siteforge-flow',JSON.stringify(config));scan();return true;
  }

  const scan=()=>{if(!allowed())return;document.querySelectorAll('[data-siteforge-flow]').forEach(element=>{
    if(instances.has(element)||failed.has(element))return;
    try {const config=JSON.parse(element.getAttribute('data-siteforge-flow'));
      if(!valid(config))return;
      if(instances.size>=4)return; // Compiler enforces the same per-page budget.
      instances.set(element,new Flow(element,config));
    }catch{failed.add(element); /* The static authored gradient remains intact. */ }
  });};
  const changed=()=>{if(!allowed()){if(frame)cancelAnimationFrame(frame);frame=0;for(const item of instances.values())item.rest();}else scan();};
  motion.addEventListener('change',changed);hover.addEventListener('change',changed);document.addEventListener('visibilitychange',changed);
  const observer=new MutationObserver(()=>{for(const item of instances.values())if(!item.element.isConnected)item.dispose();scan();});
  observer.observe(document.documentElement,{childList:true,subtree:true});
  const dispose=()=>{disposed=true;if(frame)cancelAnimationFrame(frame);frame=0;observer.disconnect();for(const item of Array.from(instances.values()))item.dispose();
    motion.removeEventListener('change',changed);hover.removeEventListener('change',changed);document.removeEventListener('visibilitychange',changed);};
  addEventListener('pagehide',event=>{if(event.persisted){suspended=true;changed();}else dispose();});
  addEventListener('pageshow',event=>{if(event.persisted&&!disposed){suspended=false;changed();}});
  Object.defineProperty(window,'SiteForgeDecorativeEffects',{value:Object.freeze({version:1,dispose,update,
    statistics:()=>Object.freeze({...stats,instances:instances.size,active:active.size,pendingFrames:frame?1:0})})});
  scan();
})();

"""#
    static let css = #"""
.sf-flow-host { position:relative; }
.sf-flow-canvas { position:absolute;inset:0;width:100%;height:100%;pointer-events:none;border-radius:inherit;z-index:-1; }
.sf-flow-canvas[hidden] { display:none; }
.sf-flow-ready { background-image:none!important;background-color:transparent!important; }
.sf-flow-ready { isolation:isolate; }

"""#
}

/// Numeric-only JSON is escaped as an HTML attribute by SafeHTMLEmitter.
/// It cannot introduce author-provided executable source.
struct FlowOutputConfiguration: Codable, Equatable, Sendable {
    struct Stop: Codable, Equatable, Sendable {
        let position: Double, red: Double, green: Double, blue: Double, alpha: Double
    }
    let version: Int
    let radius: Double, strength: Double, response: Double, returnSeconds: Double, angle: Double
    let stops: [Stop]
    init(flow: CanonicalFlowGradient, layer: CanonicalFillLayer) {
        version = 1; radius = flow.radius; strength = flow.strength; response = flow.response
        returnSeconds = flow.returnSeconds; angle = layer.normalizedAngleDegrees ?? 0
        stops = layer.stops.map { .init(position: $0.position, red: $0.color.red, green: $0.color.green, blue: $0.color.blue, alpha: $0.color.alpha) }
    }
    var json: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(data: (try? encoder.encode(self)) ?? Data(), encoding: .utf8) ?? ""
    }
}

enum DecorativeEffectOutput {
    private static func number(_ value: Double) -> String {
        String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), value)
    }
    static func configuration(_ node: DocumentNode) throws -> FlowOutputConfiguration? {
        guard let flow = try CanonicalFlowGradient.resolve(node), flow.enabled else { return nil }
        guard let layer = CanonicalFlowGradient.gradient(on: node) else { throw DesignInspectorError.unavailable(CanonicalFlowGradient.unavailableReason) }
        return .init(flow: flow, layer: layer)
    }
    static func configurations(_ page: DocumentPage) throws -> [NodeID: FlowOutputConfiguration] {
        var result: [NodeID: FlowOutputConfiguration] = [:]
        for node in page.nodes { if let value = try configuration(node) { result[node.id] = value } }
        guard result.count <= 4 else { throw DesignInspectorError.unavailable("Use at most four enabled flowing gradients per page.") }
        return result
    }
    static func glassCSS(_ nodes: [DocumentNode]) throws -> String {
        try nodes.compactMap { node -> String? in
            guard let glass = try CanonicalGlassSurface.resolve(node) else { return nil }
            let selector = ".sf-node-" + node.id.description
            let color = glass.fallback
            let fallback = "rgb(\(number(color.red * 255)) \(number(color.green * 255)) \(number(color.blue * 255)))"
            let dark = glass.darkFallback ?? color
            let darkFallback = "rgb(\(number(dark.red * 255)) \(number(dark.green * 255)) \(number(dark.blue * 255)))"
            let blur = number(glass.blur)
            return """
            @supports not ((backdrop-filter:blur(1px)) or (-webkit-backdrop-filter:blur(1px))) { \(selector) { background:\(fallback)!important; } }
            @supports ((backdrop-filter:blur(1px)) or (-webkit-backdrop-filter:blur(1px))) {
              @media (prefers-reduced-transparency:no-preference) {
                \(selector) { backdrop-filter:blur(\(blur)px);-webkit-backdrop-filter:blur(\(blur)px); }
              }
            }
            @media (prefers-reduced-transparency:reduce) { \(selector) { background:\(fallback)!important;backdrop-filter:none;-webkit-backdrop-filter:none; } }
            @media (prefers-color-scheme:dark) {
              @supports not ((backdrop-filter:blur(1px)) or (-webkit-backdrop-filter:blur(1px))) { \(selector) { background:\(darkFallback)!important; } }
              @media (prefers-reduced-transparency:reduce) { \(selector) { background:\(darkFallback)!important; } }
            }
            """
        }.joined(separator: "\n")
    }
}
