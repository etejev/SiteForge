import SwiftUI

/// Website configuration is edited with native controls. Animation runs only
/// in explicit website preview/output, never in the ordinary edit canvas.
struct DecorativeEffectsInspector: View {
    @ObservedObject var state: WorkspaceShellState
    @State private var showsLivePreview = false
    private var node: DocumentNode? { state.selectedCanonicalNodes.count == 1 ? state.selectedCanonicalNodes.first : nil }
    private var flow: CanonicalFlowGradient? { node.flatMap { try? CanonicalFlowGradient.resolve($0) } }
    private var glass: CanonicalGlassSurface? { node.flatMap { try? CanonicalGlassSurface.resolve($0) } }
    private var flowSupported: Bool { node.map { [.frame, .section].contains($0.kind) } ?? false }
    private var glassSupported: Bool { node.map { [.frame, .section, .stack, .grid, .button].contains($0.kind) } ?? false }
    var body: some View {
        if flowSupported || glassSupported {
            GroupBox("Website Effects") {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
                    if flowSupported {
                        Toggle("Flowing gradient", isOn: Binding(get: { flow?.enabled == true }, set: { enabled in
                            var next = flow ?? .defaults; next.enabled = enabled
                            commit(.flow(next))
                        })).accessibilityIdentifier("inspector.effects.flow.enabled")
                        if let flow, flow.enabled {
                            if let node, CanonicalFlowGradient.gradient(on: node) == nil {
                                Text(CanonicalFlowGradient.unavailableReason).font(.caption).foregroundStyle(.secondary)
                            }
                            effectNumber("Pull radius", value: flow.radius, range: 24...1_200, unit: "px", key: "radius") { var next = flow; next.radius = $0; return .flow(next) }
                            effectNumber("Pull strength", value: flow.strength * 100, range: 0...100, unit: "%", key: "strength") { var next = flow; next.strength = $0 / 100; return .flow(next) }
                            effectNumber("Follow response", value: flow.response, range: 0.5...30, unit: "/s", key: "response") { var next = flow; next.response = $0; return .flow(next) }
                            effectNumber("Return smoothing", value: flow.returnSeconds, range: 0.1...5, unit: "s", key: "return") { var next = flow; next.returnSeconds = $0; return .flow(next) }
                            Text("Higher response follows motion faster. Return smoothing is the time for displacement to decay to 37%. Preview the website to move the gradient.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button(showsLivePreview ? "Close Live Effect Preview" : "Live Effect Preview") { showsLivePreview.toggle() }
                                .accessibilityIdentifier("inspector.effects.flow.preview")
                            if showsLivePreview, let previewNode = state.previewedDesignStyleNode,
                               let configuration = try? DecorativeEffectOutput.configuration(previewNode) {
                                FlowEffectPreview(configuration: configuration).frame(height: 180)
                                Text("Move the pointer over this preview. The edit canvas stays still. Reduced Motion and touch-only input use the static gradient.")
                                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Button("Reset Flow") { commit(.flow(.defaults)) }.accessibilityIdentifier("inspector.effects.flow.reset")
                        }
                    }
                    if glassSupported {
                        Toggle("Glass surface", isOn: Binding(get: { glass != nil }, set: { enabled in
                            commit(.glass(enabled ? .init(blur: 16, fallback: .legacySurface) : nil))
                        })).accessibilityIdentifier("inspector.effects.glass.enabled")
                        if let glass {
                            EffectNumberControl(state: state, label: "Backdrop blur", value: glass.blur, range: 0...60, unit: "px", identifier: "inspector.effects.glass.blur") { var next = glass; next.blur = $0; return .glass(next) }
                            DesignColorEditor(state: state, color: glass.fallback, isEnabled: true,
                                label: "Opaque glass fallback", identifier: "inspector.effects.glass.fallback", allowsAlpha: false,
                                edit: { color in var next = glass; next.fallback = color; return .effect(.glass(next)) })
                            Toggle("Dark opaque fallback", isOn: Binding(get: { glass.darkFallback != nil }, set: { enabled in
                                var next = glass; next.darkFallback = enabled ? glass.fallback : nil; commit(.glass(next))
                            })).accessibilityIdentifier("inspector.effects.glass.dark.enabled")
                            if let color = glass.darkFallback {
                                DesignColorEditor(state: state, color: color, isEnabled: true,
                                    label: "Dark opaque glass fallback", identifier: "inspector.effects.glass.dark.color", allowsAlpha: false,
                                    edit: { color in var next = glass; next.darkFallback = color; return .effect(.glass(next)) })
                            }
                            Text("The opaque fallback is used without backdrop support or when reduced transparency is requested.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        } else if state.selectedCanonicalNodes.count > 1 {
            Text("Select one object to edit website effects. Mixed effects are preserved.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func effectNumber(_ label: String, value: Double, range: ClosedRange<Double>, unit: String, key: String,
                              edit: @escaping (Double) -> DecorativeEffectEdit) -> some View {
        EffectNumberControl(state: state, label: label, value: value, range: range, unit: unit,
                            identifier: "inspector.effects.flow." + key, edit: edit)
    }
    private func commit(_ edit: DecorativeEffectEdit) {
        guard state.prepareForWorkspaceAction(.context) else { return }
        let owner = UUID()
        if state.previewDesignStyle(.effect(edit), owner: owner) { _ = state.finishDesignStylePreview(owner: owner) }
    }
}

/// OD-040 (ADR-0060): state-change transitions and reveal-on-scroll. Motion
/// plays only in Preview and the exported website, never on the edit canvas.
struct MotionInspector: View {
    @ObservedObject var state: WorkspaceShellState
    private var node: DocumentNode? { state.selectedCanonicalNodes.count == 1 ? state.selectedCanonicalNodes.first : nil }
    private var current: CanonicalMotion { node.flatMap { try? CanonicalMotion.resolve($0) } ?? CanonicalMotion() }
    private var supported: Bool {
        guard let node, !state.isInspectingPageBackground else { return false }
        return CanonicalMotion.supportedKinds.contains(node.kind)
            && !node.properties.contains { $0.key.rawValue.hasPrefix("form.field.v1.") }
    }
    var body: some View {
        if supported {
            GroupBox("Motion") {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
                    Toggle("Animate state changes", isOn: Binding(get: { current.transition != nil }, set: { enabled in
                        var next = current; next.transition = enabled ? CanonicalMotion.defaultTransition : nil; commit(next)
                    })).accessibilityIdentifier("inspector.motion.transition.enabled")
                    if let transition = current.transition {
                        EffectNumberControl(state: state, label: "Transition duration", value: transition.milliseconds, range: 50...2_000,
                                            unit: "ms", identifier: "inspector.motion.transition.duration") { value in
                            var next = current; next.transition?.milliseconds = value.rounded(); return .motion(next)
                        }
                        easingPicker("Transition easing", selection: transition.easing, identifier: "inspector.motion.transition.easing") { easing in
                            var next = current; next.transition?.easing = easing; return next
                        }
                        Text("Hover, focus and pressed colors and opacity change over this time.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Toggle("Reveal when scrolled into view", isOn: Binding(get: { current.entrance != nil }, set: { enabled in
                        var next = current; next.entrance = enabled ? CanonicalMotion.defaultEntrance : nil; commit(next)
                    })).accessibilityIdentifier("inspector.motion.entrance.enabled")
                    if let entrance = current.entrance {
                        Picker("Reveal effect", selection: Binding(get: { entrance.effect }, set: { effect in
                            var next = current; next.entrance?.effect = effect; commit(next)
                        })) {
                            ForEach(CanonicalMotion.EntranceEffect.allCases, id: \.self) { Text($0.label).tag($0) }
                        }.accessibilityIdentifier("inspector.motion.entrance.effect")
                        entranceNumber("Reveal duration", value: entrance.milliseconds, range: 100...3_000, unit: "ms", key: "duration") { $0.milliseconds = $1 }
                        entranceNumber("Reveal delay", value: entrance.delayMilliseconds, range: 0...3_000, unit: "ms", key: "delay") { $0.delayMilliseconds = $1 }
                        if entrance.effect.usesDistance {
                            entranceNumber("Travel distance", value: entrance.distance, range: 0...400, unit: "px", key: "distance") { $0.distance = $1 }
                        }
                        entranceNumber("Trigger line above viewport bottom", value: entrance.offsetPercent, range: 0...50, unit: "%", key: "offset") { $0.offsetPercent = $1 }
                        easingPicker("Reveal easing", selection: entrance.easing, identifier: "inspector.motion.entrance.easing") { easing in
                            var next = current; next.entrance?.easing = easing; return next
                        }
                    }
                    Text("Motion plays in Preview and the exported website, not on this canvas. Visitors who turn on Reduce Motion, print the page or have scripts off see the content without animation.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private func entranceNumber(_ label: String, value: Double, range: ClosedRange<Double>, unit: String, key: String,
                                apply: @escaping (inout CanonicalMotion.Entrance, Double) -> Void) -> some View {
        let base = current
        return EffectNumberControl(state: state, label: label, value: value, range: range, unit: unit,
                                   identifier: "inspector.motion.entrance." + key) { input in
            var next = base
            if var entrance = next.entrance { apply(&entrance, input.rounded()); next.entrance = entrance }
            return .motion(next)
        }
    }
    private func easingPicker(_ label: String, selection: CanonicalMotion.Easing, identifier: String,
                              apply: @escaping (CanonicalMotion.Easing) -> CanonicalMotion) -> some View {
        Picker(label, selection: Binding(get: { selection }, set: { commit(apply($0)) })) {
            ForEach(CanonicalMotion.Easing.allCases, id: \.self) { Text($0.label).tag($0) }
        }.accessibilityIdentifier(identifier)
    }
    private func commit(_ next: CanonicalMotion) {
        guard state.prepareForWorkspaceAction(.context) else { return }
        let owner = UUID()
        if state.previewDesignStyle(.effect(.motion(next.isEmpty ? nil : next)), owner: owner) { _ = state.finishDesignStylePreview(owner: owner) }
    }
}

/// OD-039 (ADR-0061): the event graph of one trigger object. Interactions run
/// only in Preview and the exported website, never on the edit canvas.
struct InteractionInspector: View {
    @ObservedObject var state: WorkspaceShellState
    private var node: DocumentNode? { state.selectedCanonicalNodes.count == 1 ? state.selectedCanonicalNodes.first : nil }
    private var graph: CanonicalEventGraph { node.flatMap { try? CanonicalEventGraph.resolve($0) } ?? CanonicalEventGraph() }
    private var document: CanonicalDocument { state.documentSession.document }
    private var targets: [DocumentNode] {
        (document.pages.first { $0.id == state.effectiveSelectedPageID }?.nodes ?? []).filter { CanonicalEventGraph.supportedKinds.contains($0.kind) }
    }
    private var variables: [CanonicalStateVariable] {
        document.pages.first { $0.id == state.effectiveSelectedPageID }.map { CanonicalPageState.variables(on: $0) } ?? []
    }
    private var supported: Bool {
        guard let node, !state.isInspectingPageBackground else { return false }
        return CanonicalEventGraph.supportedKinds.contains(node.kind)
            && !node.properties.contains { $0.key.rawValue.hasPrefix("form.field.v1.") }
    }
    var body: some View {
        if supported, let node {
            GroupBox("Interactions") {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
                    Toggle("Start hidden", isOn: Binding(get: { graph.startsHidden }, set: { hidden in
                        var next = graph; next.startsHidden = hidden; commit(next)
                    })).accessibilityIdentifier("inspector.interactions.startsHidden")
                    ForEach(Array(graph.interactions.enumerated()), id: \.element.id) { index, interaction in
                        interactionEditor(index: index, interaction: interaction, node: node)
                    }
                    Button("Add Interaction") {
                        var next = graph
                        next.interactions.append(CanonicalInteraction(id: UUID(),
                            trigger: CanonicalEventGraph.clickKinds.contains(node.kind) ? .click : .viewportEnter,
                            actions: [.init(kind: .show, target: defaultTarget(node))]))
                        commit(next)
                    }
                    .disabled(graph.interactions.count >= CanonicalEventGraph.maximumInteractions)
                    .accessibilityIdentifier("inspector.interactions.add")
                    // C7 (ADR-0066): the page background lists every interaction on the page.
                    Button("Show All Interactions on This Page") {
                        if let pageID = state.effectiveSelectedPageID { state.revealPageBackground(pageID: pageID) }
                    }
                    .accessibilityIdentifier("inspector.interactions.pageOverview")
                    Text("Interactions run in Preview and the exported website, in the order listed. Click is available on buttons and links; key presses run while the object has keyboard focus; pair pointer interactions with Focus In or Focus Out for keyboard users.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private func interactionEditor(index: Int, interaction: CanonicalInteraction, node: DocumentNode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Picker("When", selection: Binding(get: { interaction.trigger }, set: { trigger in update(index) { $0.trigger = trigger } })) {
                    ForEach(CanonicalInteraction.Trigger.allCases.filter { $0 != .click || CanonicalEventGraph.clickKinds.contains(node.kind) }, id: \.self) {
                        Text($0.label).tag($0)
                    }
                }.accessibilityIdentifier("inspector.interactions.\(index).trigger")
                Button("Remove Interaction \(index + 1)") {
                    var next = graph; next.interactions.remove(at: index); commit(next)
                }.accessibilityIdentifier("inspector.interactions.\(index).remove")
            }
            if interaction.trigger.keyboardKey != nil, !CanonicalEventGraph.clickKinds.contains(node.kind) {
                Text(CanonicalEventGraph.keyFocusNote)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspector.interactions.\(index).keyFocus")
            }
            ForEach(Array(interaction.actions.enumerated()), id: \.offset) { actionIndex, action in
                actionEditor(index: index, actionIndex: actionIndex, action: action, node: node)
            }
            if let navigate = interaction.actions.firstIndex(where: { $0.kind == .navigate }), navigate < interaction.actions.count - 1 {
                Text("Actions after Go To Page never run. Move Go To Page to the end.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Button("Add Action") { update(index) { $0.actions.append(.init(kind: .show, target: defaultTarget(node))) } }
                .disabled(interaction.actions.count >= CanonicalEventGraph.maximumActions)
                .accessibilityIdentifier("inspector.interactions.\(index).addAction")
            Divider()
        }
    }
    private func actionEditor(index: Int, actionIndex: Int, action: CanonicalInteraction.Action, node: DocumentNode) -> some View {
        let pages = document.websitePages
        let overlays = targets.filter { (try? CanonicalOverlay.resolve($0)) != nil }
        let kinds = CanonicalInteraction.ActionKind.allCases.filter { kind -> Bool in
            if kind == action.kind { return true }
            switch kind {
            case .setVariable: return !variables.isEmpty
            case .toggleVariable: return variables.contains { $0.type == .boolean }
            case .openOverlay, .closeOverlay: return !overlays.isEmpty
            default: return true
            }
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Picker("Action \(actionIndex + 1)", selection: Binding(get: { action.kind }, set: { kind in update(index) { interaction in
                    interaction.actions[actionIndex] = reshaped(action, to: kind, node: node, overlays: overlays)
                } })) {
                    ForEach(kinds, id: \.self) { Text($0.label).tag($0) }
                }.accessibilityIdentifier("inspector.interactions.\(index).action.\(actionIndex).kind")
                Button("Remove Action \(actionIndex + 1)") {
                    var next = graph
                    guard next.interactions.indices.contains(index) else { return }
                    next.interactions[index].actions.remove(at: actionIndex)
                    if next.interactions[index].actions.isEmpty { next.interactions.remove(at: index) }
                    commit(next)
                }.accessibilityIdentifier("inspector.interactions.\(index).action.\(actionIndex).remove")
            }
            switch action.kind {
            case .navigate:
                Picker("Page", selection: Binding(get: { action.page }, set: { page in update(index) { $0.actions[actionIndex].page = page } })) {
                    ForEach(pages) { Text($0.name).tag(Optional($0.id)) }
                    if let page = action.page, !pages.contains(where: { $0.id == page }) { Text("Missing page").tag(Optional(page)) }
                }.accessibilityIdentifier("inspector.interactions.\(index).action.\(actionIndex).page")
            case .setVariable, .toggleVariable:
                let choices = action.kind == .toggleVariable ? variables.filter { $0.type == .boolean } : variables
                Picker("Variable", selection: Binding(get: { action.variable }, set: { id in update(index) { interaction in
                    interaction.actions[actionIndex].variable = id
                    if action.kind == .setVariable { interaction.actions[actionIndex].value = variables.first { $0.id == id }?.initial }
                } })) {
                    ForEach(choices) { Text($0.name).tag(Optional($0.id)) }
                    if let id = action.variable, !choices.contains(where: { $0.id == id }) { Text("Missing variable").tag(Optional(id)) }
                }.accessibilityIdentifier("inspector.interactions.\(index).action.\(actionIndex).variable")
                if action.kind == .setVariable, let value = action.value {
                    VariableValueField(type: variables.first { $0.id == action.variable }?.type ?? value.type, value: value, label: "To",
                                       identifier: "inspector.interactions.\(index).action.\(actionIndex).value") { next in
                        update(index) { $0.actions[actionIndex].value = next }
                    }
                }
            case .openOverlay, .closeOverlay:
                Picker("Overlay", selection: Binding(get: { action.target }, set: { target in update(index) { $0.actions[actionIndex].target = target } })) {
                    ForEach(overlays) { Text($0.name).tag(Optional($0.id)) }
                    if let target = action.target, !overlays.contains(where: { $0.id == target }) { Text("Not an overlay").tag(Optional(target)) }
                }.accessibilityIdentifier("inspector.interactions.\(index).action.\(actionIndex).overlay")
            case .show, .hide, .toggle, .focus, .scrollTo:
                Picker("Target", selection: Binding(get: { action.target }, set: { target in update(index) { $0.actions[actionIndex].target = target } })) {
                    ForEach(targets) { Text($0.name).tag(Optional($0.id)) }
                    if let target = action.target, !targets.contains(where: { $0.id == target }) { Text("Missing object").tag(Optional(target)) }
                }.accessibilityIdentifier("inspector.interactions.\(index).action.\(actionIndex).target")
            }
        }
    }
    /// Changing the action kind keeps only the fields the new kind uses.
    private func reshaped(_ action: CanonicalInteraction.Action, to kind: CanonicalInteraction.ActionKind,
                          node: DocumentNode, overlays: [DocumentNode]) -> CanonicalInteraction.Action {
        var next = CanonicalInteraction.Action(kind: kind)
        switch kind {
        case .navigate: next.page = action.page ?? document.websitePages.first?.id
        case .setVariable:
            let variable = variables.first { $0.id == action.variable } ?? variables.first
            next.variable = variable?.id; next.value = variable?.initial
        case .toggleVariable:
            next.variable = (variables.first { $0.id == action.variable && $0.type == .boolean } ?? variables.first { $0.type == .boolean })?.id
        case .openOverlay, .closeOverlay:
            next.target = overlays.contains { $0.id == action.target } ? action.target : overlays.first?.id
        case .show, .hide, .toggle, .focus, .scrollTo:
            next.target = action.target ?? defaultTarget(node)
        }
        return next
    }
    private func defaultTarget(_ node: DocumentNode) -> NodeID {
        targets.first { $0.id != node.id }?.id ?? node.id
    }
    private func update(_ index: Int, _ change: (inout CanonicalInteraction) -> Void) {
        var next = graph
        guard next.interactions.indices.contains(index) else { return }
        change(&next.interactions[index])
        commit(next)
    }
    private func commit(_ next: CanonicalEventGraph) {
        guard state.prepareForWorkspaceAction(.context) else { return }
        let owner = UUID()
        if state.previewDesignStyle(.effect(.events(next.isEmpty ? nil : next)), owner: owner) { _ = state.finishDesignStylePreview(owner: owner) }
    }
}

/// OD-039 (ADR-0062): page variables (on the page background), overlays and
/// visibility conditions. Overlays start hidden only on the website; the edit
/// canvas always shows them.
struct RuntimeStateInspector: View {
    @ObservedObject var state: WorkspaceShellState
    private var node: DocumentNode? { state.selectedCanonicalNodes.count == 1 ? state.selectedCanonicalNodes.first : nil }
    private var page: DocumentPage? { state.documentSession.document.pages.first { $0.id == state.effectiveSelectedPageID } }
    private var variables: [CanonicalStateVariable] { page.map { CanonicalPageState.variables(on: $0) } ?? [] }
    private var overlay: CanonicalOverlay? { node.flatMap { try? CanonicalOverlay.resolve($0) } }
    private var condition: CanonicalPageState.Condition? { node.flatMap { try? CanonicalPageState.condition($0) } }
    private var supportsObject: Bool {
        guard let node, !state.isInspectingPageBackground else { return false }
        return CanonicalEventGraph.supportedKinds.contains(node.kind)
            && !node.properties.contains { $0.key.rawValue.hasPrefix("form.field.v1.") }
    }
    var body: some View {
        if state.isInspectingPageBackground {
            GroupBox("Page Variables") {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
                    ForEach(Array(variables.enumerated()), id: \.element.id) { index, variable in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                VariableValueField(type: .string, value: .string(variable.name), label: "Name",
                                                   identifier: "inspector.state.variable.\(index).name", commit: { value in
                                    guard case .string(let name) = value else { return }
                                    var next = variables; next[index].name = name; commitVariables(next)
                                }, problem: { value in nameProblem(value, index: index) })
                                Picker("Type", selection: Binding(get: { variable.type }, set: { type in
                                    var next = variables; next[index].type = type; next[index].initial = type.defaultValue; commitVariables(next)
                                })) {
                                    ForEach(CanonicalStateVariable.ValueType.allCases, id: \.self) { Text($0.label).tag($0) }
                                }.accessibilityIdentifier("inspector.state.variable.\(index).type")
                                Button("Remove Variable \(index + 1)") {
                                    var next = variables; next.remove(at: index); commitVariables(next)
                                }.accessibilityIdentifier("inspector.state.variable.\(index).remove")
                            }
                            VariableValueField(type: variable.type, value: variable.initial, label: "Starts as",
                                               identifier: "inspector.state.variable.\(index).initial") { value in
                                var next = variables; next[index].initial = value; commitVariables(next)
                            }
                        }
                    }
                    Button("Add Variable") {
                        var number = variables.count + 1
                        while variables.contains(where: { $0.name == "Variable \(number)" }) { number += 1 }
                        commitVariables(variables + [CanonicalStateVariable(id: UUID(), name: "Variable \(number)", type: .boolean, initial: .boolean(false))])
                    }
                    .disabled(variables.count >= CanonicalPageState.maximumVariables)
                    .accessibilityIdentifier("inspector.state.addVariable")
                    Text("Variables reset each time a visitor opens the page; nothing is stored. Interactions can set them and objects can be visible only while a variable has a value. Changing a type leaves existing uses for you to update; Check Website lists them.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            PageInteractionsOverview(state: state)
        } else if supportsObject, let node {
            GroupBox("Overlay and Visibility") {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
                    if CanonicalOverlay.supportedKinds.contains(node.kind) {
                        Toggle("Overlay", isOn: Binding(get: { overlay != nil }, set: { enabled in
                            commit(.overlay(enabled ? CanonicalOverlay.defaults : nil))
                        })).accessibilityIdentifier("inspector.overlay.enabled")
                        if let overlay { overlayControls(overlay) }
                    }
                    if overlay != nil && condition == nil {
                        // The website ignores a condition on an overlay (Check Website reports one).
                        Text("An overlay is shown and hidden by its interactions, so it has no visibility condition.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else if variables.isEmpty && condition == nil {
                        Text("Add page variables on the page background to show this object only while a variable has a value.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Toggle("Visible only when a variable matches", isOn: Binding(get: { condition != nil }, set: { enabled in
                            guard enabled else { commit(.visibility(nil)); return }
                            guard let first = variables.first else { return }
                            commit(.visibility(CanonicalPageState.Condition(variable: first.id, equals: first.initial)))
                        })).accessibilityIdentifier("inspector.visibility.enabled")
                        if let condition {
                            Picker("Variable", selection: Binding(get: { condition.variable }, set: { id in
                                let value = variables.first { $0.id == id }?.initial ?? condition.equals
                                commit(.visibility(CanonicalPageState.Condition(variable: id, equals: value)))
                            })) {
                                ForEach(variables) { Text($0.name).tag($0.id) }
                                if !variables.contains(where: { $0.id == condition.variable }) { Text("Missing variable").tag(condition.variable) }
                            }.accessibilityIdentifier("inspector.visibility.variable")
                            VariableValueField(type: variables.first { $0.id == condition.variable }?.type ?? condition.equals.type,
                                               value: condition.equals, label: "Equals", identifier: "inspector.visibility.value") { value in
                                commit(.visibility(CanonicalPageState.Condition(variable: condition.variable, equals: value)))
                            }
                        }
                    }
                    if node.kind == .text { textBindingControls(node) }
                }
            }
        }
    }
    /// Overlay type, outside-click dismissal and, for a popover or menu, where
    /// it opens (SF-1105-002, ADR-0065).
    @ViewBuilder private func overlayControls(_ overlay: CanonicalOverlay) -> some View {
        Picker("Overlay type", selection: Binding(get: { overlay.kind }, set: { kind in
            var next = overlay; next.kind = kind
            // A modal is always centred, so it keeps no placement.
            if kind == .modal { next.placement = nil }
            commit(.overlay(next))
        })) {
            ForEach(CanonicalOverlay.Kind.allCases, id: \.self) { Text($0.label).tag($0) }
        }.accessibilityIdentifier("inspector.overlay.kind")
        if overlay.kind != .modal {
            Picker("Opens", selection: Binding(get: { overlay.placement }, set: { placement in
                var next = overlay; next.placement = placement; commit(.overlay(next))
            })) {
                Text("Where It Is Drawn").tag(CanonicalOverlay.Placement?.none)
                ForEach(CanonicalOverlay.Placement.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
            }.accessibilityIdentifier("inspector.overlay.placement")
        }
        Toggle("Close when clicking outside", isOn: Binding(get: { overlay.dismissesOnOutsideClick }, set: { value in
            var next = overlay; next.dismissesOnOutsideClick = value; commit(.overlay(next))
        })).accessibilityIdentifier("inspector.overlay.dismissOutside")
        Text("On the website this starts hidden and opens with an Open Overlay interaction. Escape closes it and focus returns to the control that opened it. A modal dialog is centred and keeps keyboard focus inside. A popover or menu opens where it is drawn or next to the object whose interaction opens it, on the other side when there is no room; arrow keys move through a menu. Give it an Accessible name.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    /// C6 (SF-1106-002/003/004, ADR-0066): the Text shows a page variable's
    /// value on the website. The status line says which value the website
    /// shows and why, including when the variable is missing.
    @ViewBuilder private func textBindingControls(_ node: DocumentNode) -> some View {
        let binding: CanonicalTextBinding? = try? CanonicalTextBinding.resolve(node)
        if variables.isEmpty && binding == nil {
            Text("Add page variables on the page background to show a variable's value in this text.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else {
            Toggle("Show a variable's value", isOn: Binding(get: { binding != nil }, set: { enabled in
                guard enabled else { commit(.textBinding(nil)); return }
                guard let first = variables.first else { return }
                commit(.textBinding(CanonicalTextBinding(variable: first.id)))
            })).accessibilityIdentifier("inspector.textBinding.enabled")
            if let binding {
                let missing = !variables.contains { $0.id == binding.variable }
                Picker("Shows", selection: Binding(get: { binding.variable }, set: { id in
                    commit(.textBinding(CanonicalTextBinding(variable: id)))
                })) {
                    ForEach(variables) { Text($0.name).tag($0.id) }
                    if missing { Text("Missing variable").tag(binding.variable) }
                }.accessibilityIdentifier("inspector.textBinding.variable")
                Text(CanonicalTextBinding.status(binding, variables: variables))
                    .font(.caption).foregroundStyle(missing ? SiteForgeVisualSystem.danger : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspector.textBinding.status")
            }
        }
    }
    /// Why a variable name cannot be stored, or nil. Names are unique on the page.
    private func nameProblem(_ value: CanonicalVariableValue, index: Int) -> String? {
        guard case .string(let name) = value, CanonicalStateVariable.validName(name) else {
            return "Enter a name of 1–64 bytes without spaces at the start or end."
        }
        return variables.indices.contains { $0 != index && variables[$0].name == name } ? "Another variable on this page already has this name." : nil
    }
    private func commitVariables(_ next: [CanonicalStateVariable]) {
        guard CanonicalPageState.isValid(next) else { return }
        commit(.pageVariables(next))
    }
    private func commit(_ edit: DecorativeEffectEdit) {
        guard state.prepareForWorkspaceAction(.context) else { return }
        let owner = UUID()
        if state.previewDesignStyle(.effect(edit), owner: owner) { _ = state.finishDesignStylePreview(owner: owner) }
    }
}

/// C7 (SF-1101-002/003, ADR-0066): every interaction on the page, listed on
/// the page background in Layers order. Each row is a button (Tab, Space and
/// VoiceOver reach it) that selects its object on the canvas.
struct PageInteractionsOverview: View {
    @ObservedObject var state: WorkspaceShellState
    private var summaries: [PageInteractionSummary] {
        let document = state.documentSession.document
        guard let page = document.pages.first(where: { $0.id == state.effectiveSelectedPageID }) else { return [] }
        return PageInteractionOverview.summaries(page, websitePages: document.websitePages)
    }
    var body: some View {
        let rows = summaries
        GroupBox("Page Interactions") {
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.controlInset) {
                if rows.isEmpty {
                    Text("No object on this page has interactions. Select an object and choose Add Interaction.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("inspector.pageInteractions.empty")
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        PageInteractionRow(summary: row) { _ = state.revealInteractionObject(row.nodeID) }
                            .accessibilityIdentifier("inspector.pageInteractions.\(index)")
                    }
                    Text("Listed in Layers order. Choose one to select its object.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct PageInteractionRow: View {
    let summary: PageInteractionSummary
    let select: () -> Void
    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.objectName + " \u{2014} " + summary.trigger.label)
                Text(summary.actions.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if summary.unavailableActions > 0 {
                    Text("\(summary.unavailableActions) action\(summary.unavailableActions == 1 ? "" : "s") cannot run; Check Website explains why.")
                        .font(.caption).foregroundStyle(SiteForgeVisualSystem.danger)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(summary.accessibilityLabel)
        .accessibilityHint("Selects this object on the canvas.")
    }
}

/// Edits one typed value: a toggle for true/false, a field committed on
/// Return for numbers and text. An entry that cannot be stored stays in the
/// field with a caption that says why (`problem` adds the caller's rules, such
/// as unique names); the document is unchanged until the entry is valid.
struct VariableValueField: View {
    static let numberProblem = "Enter a whole number from −1,000,000,000 to 1,000,000,000."
    static let textProblem = "Use at most 256 bytes, without line breaks or other control characters."
    let type: CanonicalStateVariable.ValueType
    let value: CanonicalVariableValue
    let label: String
    let identifier: String
    let commit: (CanonicalVariableValue) -> Void
    var problem: (CanonicalVariableValue) -> String? = { _ in nil }
    @State private var draft: String?
    @State private var validation: String?
    var body: some View {
        switch type {
        case .boolean:
            Toggle(label, isOn: Binding(get: { value == .boolean(true) }, set: { commit(.boolean($0)) }))
                .accessibilityIdentifier(identifier)
        case .number, .string:
            VStack(alignment: .leading, spacing: 3) {
                TextField(label, text: Binding(get: { draft ?? value.text }, set: { draft = $0; validation = nil }))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submit() }
                    .onExitCommand { draft = nil; validation = nil }
                    .accessibilityLabel(label)
                    .accessibilityIdentifier(identifier)
                if let validation {
                    Text(validation).font(.caption).foregroundStyle(SiteForgeVisualSystem.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(identifier + ".validation")
                }
            }
        }
    }
    private func submit() {
        guard let text = draft else { return }
        let next: CanonicalVariableValue
        if type == .number {
            guard let number = Double(text.trimmingCharacters(in: .whitespaces)) else { reject(Self.numberProblem); return }
            next = .number(number)
        } else {
            next = .string(text)
        }
        guard next.isValid else { reject(type == .number ? Self.numberProblem : Self.textProblem); return }
        if let message = problem(next) { reject(message); return }
        draft = nil; validation = nil
        if next != value { commit(next) }
    }
    /// The caption stays under the field and VoiceOver hears it (SF-1106-006, ADR-0066).
    private func reject(_ message: String) {
        validation = message
        AccessibilityAnnouncementPoster.native.post(message)
    }
}

private struct EffectNumberControl: View {
    @ObservedObject var state: WorkspaceShellState
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let unit: String
    let identifier: String
    let edit: (Double) -> DecorativeEffectEdit
    @State private var owner = UUID()
    @State private var draft: String?
    @State private var displayed: Double?
    @State private var context: ResponsiveInspectorEditContext?
    @State private var validation: String?
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption)
            HStack(spacing: 6) {
                DesignStyleSlider(minimum: range.lowerBound, value: displayed ?? value,
                    maximum: range.upperBound, isEnabled: true, label: label + " " + unit,
                    identifier: identifier + ".slider", context: state.responsiveInspectorEditContext,
                    begin: { validation == nil }, preview: { update($0) }, finish: { _ = finish() }, cancel: { cancel() })
                TextField(label, text: Binding(get: { draft ?? DesignStyleNumberText.string(displayed ?? value) }, set: { text in
                    guard text != (draft ?? DesignStyleNumberText.string(displayed ?? value)) else { return }
                    if context == nil { context = state.responsiveInspectorEditContext }
                    draft = text
                    guard let next = Double(text), next.isFinite, range.contains(next) else {
                        validation = "Enter \(DesignStyleNumberText.string(range.lowerBound))–\(DesignStyleNumberText.string(range.upperBound)) \(unit)."; return
                    }
                    update(next)
                })).textFieldStyle(.roundedBorder).monospacedDigit().frame(width: 65)
                    .focused($focused).onSubmit { _ = finish() }
                    .onChange(of: focused) { old, new in if old && !new { _ = finish() } }
                    .accessibilityLabel(label + " " + unit).accessibilityIdentifier(identifier + ".value")
                Text(unit).font(.caption).foregroundStyle(.secondary).frame(minWidth: 18)
            }
            if let validation { Text(validation).font(.caption).foregroundStyle(SiteForgeVisualSystem.danger) }
        }
        .onExitCommand { cancel() }
        .onDisappear { cancel() }
        .onChange(of: state.responsiveInspectorEditContext) { _, _ in cancel() }
        .onReceive(state.designStyleCancellation) { cancel() }
        .onReceive(state.editCommitRequests) { request in
            guard request.isAccepted, draft != nil || displayed != nil else { return }
            if request.requiresCleanEditors || !finish() { request.reject() }
        }
    }
    private func update(_ next: Double) {
        if context == nil { context = state.responsiveInspectorEditContext }
        guard state.previewDesignStyle(.effect(edit(next)), owner: owner, expectedContext: context) else {
            validation = state.lastDesignInspectorAnnouncement; return
        }
        displayed = next; validation = nil
    }
    @discardableResult private func finish() -> Bool {
        guard validation == nil else { return false }
        guard state.finishDesignStylePreview(owner: owner) else { validation = state.lastDesignInspectorAnnouncement; return false }
        draft = nil; displayed = nil; context = nil; return true
    }
    private func cancel() {
        state.cancelDesignStylePreview(owner: owner); draft = nil; displayed = nil; context = nil; validation = nil
    }
}


import WebKit

/// A deliberately opened, isolated website effect preview. There are no app
/// message handlers, filesystem access or remote requests in this WebKit view.
struct FlowEffectPreview: NSViewRepresentable {
    let configuration: FlowOutputConfiguration
    func makeCoordinator() -> Coordinator { Coordinator(configuration: configuration) }
    func makeNSView(context: Context) -> WKWebView {
        let settings = WKWebViewConfiguration()
        settings.websiteDataStore = .nonPersistent()
        settings.setURLSchemeHandler(context.coordinator, forURLScheme: "siteforge-effect")
        let view = WKWebView(frame: .zero, configuration: settings)
        view.navigationDelegate = context.coordinator
        view.setAccessibilityLabel("Live flowing gradient preview")
        view.load(URLRequest(url: URL(string: "siteforge-effect://preview/index.html")!))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.configuration != configuration else { return }
        context.coordinator.configuration = configuration
        context.coordinator.update(view)
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading(); view.navigationDelegate = nil
        view.loadHTMLString("", baseURL: nil)
    }
    @MainActor final class Coordinator: NSObject, WKURLSchemeHandler, WKNavigationDelegate {
        var configuration: FlowOutputConfiguration
        private var ready = false
        init(configuration: FlowOutputConfiguration) { self.configuration = configuration }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; update(webView) }
        func update(_ webView: WKWebView) {
            guard ready else { return }
            // Only validated numeric configuration is serialized. The program
            // itself is fixed SiteForge-owned code and has no author text.
            webView.evaluateJavaScript("""
                (()=>{const c=\(configuration.json),e=document.getElementById('preview');
                e.style.backgroundImage='linear-gradient('+(c.angle+90)+'deg,'+c.stops.map(s=>'rgba('+s.red*255+','+s.green*255+','+s.blue*255+','+s.alpha+') '+s.position*100+'%').join(',')+')';
                window.SiteForgeDecorativeEffects.update(e,c);})();
                """)
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            decisionHandler(Self.navigationPolicy(for: navigationAction.request.url))
        }
        static func navigationPolicy(for url: URL?) -> WKNavigationActionPolicy {
            guard let url, url.scheme == "siteforge-effect", url.host == "preview",
                  url.path == "/index.html" else { return .cancel }
            return .allow
        }
        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            guard let url = urlSchemeTask.request.url, url.host == "preview" else {
                urlSchemeTask.didFailWithError(URLError(.resourceUnavailable)); return
            }
            let content: String, type: String
            switch url.path {
            case "/index.html":
                content = Self.html(configuration); type = "text/html"
            case "/effect.js": content = DecorativeEffectRuntime.javascript; type = "text/javascript"
            case "/preview.css": content = Self.css; type = "text/css"
            default: urlSchemeTask.didFailWithError(URLError(.resourceUnavailable)); return
            }
            let data = Data(content.utf8)
            urlSchemeTask.didReceive(URLResponse(url: url, mimeType: type, expectedContentLength: data.count, textEncodingName: "utf-8"))
            urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
        }
        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
        static let css = """
        html,body { margin:0;width:100%;height:100%;overflow:hidden; }
        #preview { width:100%;height:100%;position:relative; }
        """ + DecorativeEffectRuntime.css
        static func html(_ config: FlowOutputConfiguration) -> String {
            let escaped = config.json.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;")
            return """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none';script-src siteforge-effect:;style-src siteforge-effect:;connect-src 'none';img-src 'none';base-uri 'none';form-action 'none'"><link rel="stylesheet" href="preview.css"></head><body><div id="preview" data-siteforge-flow="\(escaped)"></div><script src="effect.js"></script></body></html>
            """
        }
    }
}
