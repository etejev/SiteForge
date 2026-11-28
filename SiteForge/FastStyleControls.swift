import Combine
import SwiftUI

/// Local drafts and native-panel ownership never become canonical document data.
struct DesignColorEditor: View {
    @ObservedObject var state: WorkspaceShellState
    let color: CanonicalSolidColor
    let isEnabled: Bool
    let label: String
    let identifier: String
    var hexIdentifier: String? = nil
    var hexLabel: String? = nil
    var committedHex: String? = nil
    var allowsAlpha = true
    var compactDetails = false
    let edit: (CanonicalSolidColor) -> DesignStylePreviewEdit
    @State private var owner = UUID()
    @State private var hexDraft: String?
    @State private var alphaDraft: String?
    @State private var preview: CanonicalSolidColor?
    @State private var validation: String?
    @FocusState private var field: Field?
    private enum Field { case hex, alpha }
    private var displayed: CanonicalSolidColor { preview ?? color }
    private var hexText: String { hexDraft ?? (preview == nil ? committedHex ?? color.hexadecimalRGBA : displayed.hexadecimalRGBA) }
    private var alphaText: String { alphaDraft ?? DesignStyleNumberText.string(displayed.alpha * 100) }


    var body: some View {
        let context = state.responsiveInspectorEditContext
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if !compactDetails {
                    NativeDesignColorWell(allowsAlpha: allowsAlpha, color: displayed, isEnabled: isEnabled,
                        accessibilityValue: displayed.hexadecimalRGBA,
                        accessibilityHint: "Open Colors. Changes preview live; close or leave the well to commit, Escape cancels.",
                        accessibilityIdentifier: identifier, accessibilityLabel: label,
                        onEnd: { finish() }, onCancel: { cancel() },
                        onCommit: { next in
                            hexDraft = nil; alphaDraft = nil
                            update(next, context: context)
                        })
                        .frame(width: 34, height: 24)
                        .id(state.geometryInspectorSelectionKey)
                }
                TextField("#RRGGBB", text: Binding(get: { hexText }, set: { text in
                    guard text != hexText else { return }
                    hexDraft = text
                    guard let next = CanonicalSolidColor.parse(hexadecimal: text) else {
                        validation = "Use #RRGGBB or #RRGGBBAA."; return
                    }
                    update(next, context: context)
                }))
                .textFieldStyle(.roundedBorder).monospaced()
                .focused($field, equals: .hex)
                .onSubmit { finish() }
                .accessibilityLabel(hexLabel ?? label + " hexadecimal RGBA")
                .accessibilityIdentifier(hexIdentifier ?? identifier + ".hex")
            }
            if allowsAlpha { HStack(spacing: 6) {
                Text("Alpha").font(.caption).foregroundStyle(.secondary)
                if !compactDetails {
                    DesignStyleSlider(value: displayed.alpha * 100, maximum: 100, isEnabled: isEnabled,
                        label: label + " alpha", identifier: identifier + ".alphaSlider", context: context,
                        begin: { validation == nil },
                        preview: { value in update(.init(red: displayed.red, green: displayed.green,
                            blue: displayed.blue, alpha: value / 100), context: context) },
                        finish: { finish() }, cancel: { cancel() })
                        .frame(minWidth: 50)
                }
                TextField("Alpha", text: Binding(get: { alphaText }, set: { text in
                    guard text != alphaText else { return }
                    alphaDraft = text
                    guard let value = Double(text), value.isFinite, (0...100).contains(value) else {
                        validation = "Alpha must be 0–100%."; return
                    }
                    update(.init(red: displayed.red, green: displayed.green, blue: displayed.blue, alpha: value / 100), context: context)
                }))
                .textFieldStyle(.roundedBorder).monospacedDigit().frame(width: 44)
                .focused($field, equals: .alpha).onSubmit { finish() }
                .accessibilityLabel(label + " alpha percent")
                .accessibilityIdentifier(identifier + ".alpha")
                Text("%").font(.caption).foregroundStyle(.secondary)
            }
            }
            if let validation { Text(validation).font(.caption).foregroundStyle(SiteForgeVisualSystem.danger)
                .accessibilityIdentifier(identifier + ".validation") }
        }
        .disabled(!isEnabled)
        .onChange(of: field) { old, next in if old != nil && old != next { finish() } }
        .onChange(of: state.responsiveInspectorEditContext) { _, _ in cancel() }
        .onReceive(state.designStyleCancellation) { cancel() }
        .onDisappear { cancel() }
        .onExitCommand { cancel(); field = nil }
        .onReceive(state.editCommitRequests) { request in
            guard request.isAccepted else { return }
            if request.requiresCleanEditors, preview != nil || hexDraft != nil || alphaDraft != nil { request.reject(); return }
            guard validation == nil else { request.reject(); return }
            if !finish() { request.reject() }
        }
    }

    private func update(_ next: CanonicalSolidColor, context: ResponsiveInspectorEditContext) {
        guard isEnabled else { return }
        guard allowsAlpha || next.alpha == 1 else { validation = "Use an opaque fallback color (alpha 100%)."; return }
        guard state.previewDesignStyle(edit(next), owner: owner, expectedContext: context) else {
            validation = state.lastDesignInspectorAnnouncement; return
        }
        preview = next; validation = nil
    }
    @discardableResult private func finish() -> Bool {
        guard validation == nil else { return false }
        guard preview != nil || hexDraft != nil || alphaDraft != nil else { return true }
        guard state.finishDesignStylePreview(owner: owner) else {
            validation = state.lastDesignInspectorAnnouncement; return false
        }
        preview = nil; hexDraft = nil; alphaDraft = nil
        return true
    }
    private func cancel() {
        state.cancelDesignStylePreview(owner: owner)
        preview = nil; hexDraft = nil; alphaDraft = nil; validation = nil
    }
}


/// The active layer is editor selection, not an extra authored fill.
struct FastFillInspectorView: View {
    @ObservedObject var state: WorkspaceShellState
    @Binding var activeID: FillLayerID?
    private var layers: [CanonicalFillLayer] { state.designInspectorFillLayers() }
    private var active: CanonicalFillLayer? {
        layers.first { $0.id == activeID } ?? layers.last(where: \.isEnabled) ?? layers.last
    }
    private var resolvedSolid: CanonicalSolidColor {
        if case .single(let color, _) = state.designInspectorFillValue(), layers.count <= 1 { return color }
        return active?.solidColor ?? .init(red: 0, green: 0, blue: 0, alpha: 0)
    }
    private var resolvedHex: String {
        if case .single(let color, _) = state.designInspectorFillValue(), layers.count <= 1 { return color.hexadecimalRGBA }
        return active?.solidColor?.hexadecimalRGBA ?? ""
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Fill").font(.headline)
                Spacer(minLength: 0)
                if layers.count > 1 {
                    Picker("Active fill layer", selection: Binding(get: { active?.id }, set: { next in if state.prepareForWorkspaceAction(.context) { activeID = next } })) {
                        ForEach(Array(layers.enumerated()), id: \.element.id) { index, layer in
                            Text("\(index + 1) · \(layer.kind == .solid ? "Solid" : "Gradient")\(layer.isEnabled ? "" : " (off)")").tag(Optional(layer.id))
                        }
                    }.labelsHidden().accessibilityIdentifier("inspector.design.fill.activeLayer")
                }
            }
            if let reason = state.designInspectorLayerEditingReason {
                DesignColorEditor(state: state, color: resolvedSolid, isEnabled: false,
                    label: "Solid fill color", identifier: "inspector.design.fillPicker",
                    hexIdentifier: "inspector.design.fillHex", hexLabel: "Solid fill hexadecimal RGBA", committedHex: reason,
                    edit: { .fill(.replaceSolid($0)) })
                Text(reason).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspector.design.fill.unavailable")
            } else if state.hasBoundColorTokenSelection {
                DesignColorEditor(state: state, color: resolvedSolid, isEnabled: false,
                    label: "Solid fill color", identifier: "inspector.design.fillPicker",
                    hexIdentifier: "inspector.design.fillHex", hexLabel: "Solid fill hexadecimal RGBA", committedHex: resolvedHex,
                    edit: { .fill(.replaceSolid($0)) })
                Text(state.selectedColorTokenStatus() ?? "Token-bound fill")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Unbind the fill token below to edit literal colors.").font(.caption)
            } else {
                Picker("Fill type", selection: Binding(get: { active?.kind ?? .solid }, set: { kind in changeKind(kind) })) {
                    Text("Solid").tag(CanonicalFillLayerKind.solid)
                    Text("Linear gradient").tag(CanonicalFillLayerKind.linearGradient)
                }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("inspector.design.fill.kind")
                if let active {
                    if active.kind == .solid {
                        DesignColorEditor(state: state, color: layers.count <= 1 ? resolvedSolid : active.solidColor ?? .legacySurface, isEnabled: active.isEnabled,
                            label: "Solid fill color", identifier: "inspector.design.fillPicker",
                            hexIdentifier: "inspector.design.fillHex", hexLabel: "Solid fill hexadecimal RGBA", committedHex: resolvedHex,
                            edit: { .fill(.setSolidColor(active.id, $0)) })
                            .id("quick-fill-" + active.id.description)
                    } else {
                        GradientRampEditor(state: state, layer: active)
                            .id(active.id)
                    }
                    HStack {
                        Text(active.isEnabled ? "Editing active fill" : "Active fill disabled")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove") { _ = state.commitDesignFillLayer(.remove(active.id), operation: "remove active fill") }
                            .accessibilityIdentifier("inspector.design.fillRemove")
                    }
                } else {
                    DesignColorEditor(state: state, color: resolvedSolid, isEnabled: state.canEditDesignSolidFill,
                        label: "Solid fill color", identifier: "inspector.design.fillPicker",
                        hexIdentifier: "inspector.design.fillHex", hexLabel: "Solid fill hexadecimal RGBA", committedHex: resolvedHex,
                        edit: { .fill(.replaceSolid($0)) })
                    HStack {
                        Text(resolvedHex.isEmpty ? "No fill" : "Inherited fill").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove") { _ = state.commitDesignFill(nil) }
                            .accessibilityIdentifier("inspector.design.fillRemove")
                    }
                }
            }
        }
    }
    private func changeKind(_ kind: CanonicalFillLayerKind) {
        guard active?.kind != kind, state.prepareForWorkspaceAction(.context) else { return }
        let color = active?.solidColor ?? active?.stops.first?.color ?? .legacySurface
        let id = active?.id ?? FillLayerID()
        let blue = CanonicalSolidColor(red: 0.18, green: 0.36, blue: 0.86, alpha: color.alpha)
        let endpoint = abs(color.red - blue.red) + abs(color.green - blue.green) + abs(color.blue - blue.blue) < 0.25
            ? CanonicalSolidColor(red: 1, green: 1, blue: 1, alpha: color.alpha) : blue
        let replacement: CanonicalFillLayer = kind == .solid
            ? .solid(id: id, color: color, isEnabled: active?.isEnabled ?? true)
            : .linearGradient(id: id, angleDegrees: 0, stops: [
                .init(id: GradientStopID(), position: 0, color: color),
                .init(id: GradientStopID(), position: 1, color: endpoint)],
                isEnabled: active?.isEnabled ?? true)
        if active != nil {
            _ = state.commitDesignFillLayer(.replaceLayer(replacement), operation: "fill type")
        } else if kind == .linearGradient {
            _ = state.commitDesignFillLayer(.addLinearGradient(id: id, angleDegrees: 0, stops: replacement.stops), operation: "gradient fill")
        }
    }
}

struct GradientRampEditor: View {
    @ObservedObject var state: WorkspaceShellState
    let layer: CanonicalFillLayer
    @State private var selectedID: GradientStopID?
    @State private var detailsShown = false
    @State private var colorRequest: UUID?

    private var stop: CanonicalGradientStop? {
        layer.stops.first { $0.id == selectedID } ?? layer.stops.first
    }
    private var prefix: String { "inspector.design.ramp." + layer.id.description }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NativeGradientRamp(state: state, layer: layer, selectedID: stop?.id, prefix: prefix, colorRequest: colorRequest) {
                selectedID = $0
            }
            .frame(height: 40)
            if let stop {
                HStack(spacing: 6) {
                    Picker("Gradient stop", selection: Binding(
                        get: { stop.id },
                        set: { next in
                            if state.prepareForWorkspaceAction(.context) { selectedID = next }
                        }
                    )) {
                        ForEach(Array(layer.stops.enumerated()), id: \.element.id) { index, candidate in
                            Text("Stop \(index + 1) · \(DesignStyleNumberText.string(candidate.position * 100))%")
                                .tag(candidate.id)
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier(prefix + ".selection")
                    Button { colorRequest = UUID() } label: { Image(systemName: "paintpalette") }
                        .accessibilityLabel("Choose Selected Stop Color")
                        .accessibilityIdentifier(prefix + ".chooseColor")
                    Spacer(minLength: 0)
                    Button { addStop() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add Stop")
                        .accessibilityIdentifier(prefix + ".addStop")
                        .disabled(GradientAuthoringInsertion.stop(in: layer) == nil)
                    Button {
                        _ = state.commitDesignFillLayer(.removeStop(layer.id, stop.id), operation: "remove gradient stop")
                    } label: { Image(systemName: "minus") }
                        .accessibilityLabel("Remove selected stop")
                        .accessibilityIdentifier(prefix + ".removeStop")
                        .disabled(layer.stops.count <= 2)
                        .help(layer.stops.count <= 2 ? "Keep at least two stops." : "Remove the selected stop.")
                }
                .controlSize(.small)
                DisclosureGroup("Stop Details", isExpanded: $detailsShown) {
                    stopDetails(stop).id(stop.id)
                }
                .disclosureGroupStyle(SiteForgeInspectorDisclosureStyle(identifier: prefix + ".details"))
            }
            HStack(spacing: 6) {
                Text("Direction").font(.caption)
                GradientNumberField(state: state, value: layer.normalizedAngleDegrees ?? 0, label: "Gradient direction",
                                    identifier: prefix + ".angle", percentage: false) { value in
                    state.commitDesignFillLayer(.setGradientAngle(layer.id, value), operation: "gradient direction", provenance: .keyboard)
                }
                Text("°").font(.caption)
            }
        }
        .disabled(!layer.isEnabled)
    }

    private func addStop() {
        guard let stop = GradientAuthoringInsertion.stop(in: layer),
              state.commitDesignFillLayer(.addStop(layer.id, stop, at: layer.stops.count),
                                          operation: "add gradient stop") else { return }
        selectedID = stop.id
    }

    private func stopDetails(_ stop: CanonicalGradientStop) -> some View {
        let index = layer.stops.firstIndex { $0.id == stop.id } ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Position").font(.caption)
                GradientNumberField(state: state, value: stop.position * 100, label: "Selected stop position",
                                    identifier: prefix + ".position", percentage: true) { value in
                    state.commitDesignFillLayer(.setStop(layer.id, stop.id, position: value / 100, color: stop.color),
                                               operation: "gradient stop position", provenance: .keyboard)
                }
                Text("%").font(.caption)
            }
            DesignColorEditor(state: state, color: stop.color, isEnabled: layer.isEnabled,
                label: "Selected gradient stop", identifier: prefix + ".color", compactDetails: true,
                edit: { .fill(.setStop(layer.id, stop.id, position: stop.position, color: $0)) })
            HStack {
                Button("Move Earlier") { reorder(stop, to: index - 1) }
                    .disabled(index == 0)
                    .accessibilityIdentifier(prefix + ".earlier")
                Button("Move Later") { reorder(stop, to: index + 1) }
                    .disabled(index == layer.stops.count - 1)
                    .accessibilityIdentifier(prefix + ".later")
            }
            .controlSize(.small)
            .help("Stop order controls which color comes first at a shared position.")
        }
    }

    private func reorder(_ stop: CanonicalGradientStop, to index: Int) {
        _ = state.commitDesignFillLayer(.reorderStop(layer.id, stop.id, to: index), operation: "reorder gradient stop")
    }
}

private struct GradientNumberField: View {
    @ObservedObject var state: WorkspaceShellState
    let value: Double
    let label: String
    let identifier: String
    let percentage: Bool
    let commit: (Double) -> Bool
    @State private var context: ResponsiveInspectorEditContext?
    @State private var draft: String?
    @State private var validation: String?
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField(label, text: Binding(get: { draft ?? DesignStyleNumberText.string(value) }, set: { if draft == nil { context = state.responsiveInspectorEditContext }; draft = $0; validation = nil }))
                .textFieldStyle(.roundedBorder).monospacedDigit().focused($focused)
                .onSubmit { finish() }.onChange(of: focused) { old, new in if old && !new { finish() } }
                .accessibilityLabel(label).accessibilityIdentifier(identifier)
            if let validation { Text(validation).font(.caption).foregroundStyle(SiteForgeVisualSystem.danger) }
        }.frame(maxWidth: 80)
        .onExitCommand { draft = nil; validation = nil; context = nil }
        .onReceive(state.designStyleCancellation) { draft = nil; validation = nil; context = nil }
        .onReceive(state.editCommitRequests) { request in
            guard request.isAccepted, draft != nil else { return }
            if request.requiresCleanEditors || !finish() { request.reject() }
        }
    }
    @discardableResult private func finish() -> Bool {
        guard let draft else { return true }
        guard context == state.responsiveInspectorEditContext else { validation = "Selection changed. Press Escape and re-enter this value."; return false }
        let result = percentage ? FillLayerNumericDraftValidator.percentage(draft).map { $0 * 100 } : FillLayerNumericDraftValidator.angle(draft)
        switch result { case .success(let value):
            guard commit(value) else { validation = state.lastDesignInspectorAnnouncement; return false }
            self.draft = nil; validation = nil; context = nil; return true
        case .failure(let failure): validation = failure.message; return false }
    }
}


/// Native autorepeat previews continuously and closes one undo boundary on
/// mouse-up/key-up. Independent accessibility increments are discrete edits.
struct DesignStyleStepper: NSViewRepresentable {
    let value: Double
    let maximum: Double
    let isEnabled: Bool
    let label: String
    let identifier: String
    var unit = "points"
    let preview: (Double) -> Void
    let finish: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(preview: preview) }
    func makeNSView(context: Context) -> AccessibleDesignOpacityStepper {
        let view = AccessibleDesignOpacityStepper(frame: .zero)
        view.minValue = 0; view.maxValue = maximum; view.increment = 1
        view.valueWraps = false; view.autorepeat = true
        view.target = context.coordinator; view.action = #selector(Coordinator.changed(_:))
        return view
    }
    func updateNSView(_ view: AccessibleDesignOpacityStepper, context: Context) {
        context.coordinator.preview = preview
        view.target = context.coordinator; view.action = #selector(Coordinator.changed(_:))
        view.onInteractionEnd = finish
        view.isEnabled = isEnabled; view.maxValue = maximum
        if !view.isContinuousInteraction { view.doubleValue = value }
        view.setAccessibilityLabel(label); view.setAccessibilityIdentifier(identifier)
        view.authoredAccessibilityValue = DesignStyleNumberText.string(value) + " " + unit
    }
    @MainActor final class Coordinator: NSObject {
        var preview: (Double) -> Void
        init(preview: @escaping (Double) -> Void) { self.preview = preview }
        @objc func changed(_ sender: NSStepper) {
            preview(sender.doubleValue)
        }
    }
}

/// Typed intent shared by owned color and numeric paint previews.
enum DesignStylePreviewEdit: Sendable { case fill(DesignFillLayerEdit), box(DesignBoxStyleEdit), opacity(Double), typography(TypographyEdit), effect(DecorativeEffectEdit) }

/// One sRGB paint path for the canvas tiles and editable gradient ramp.
enum NativeAuthoredFillPainter {
    static func draw(_ layer: CanvasAuthoredFillLayer, in rect: CGRect, context: CGContext) {
        guard layer.isValid else { return }
        switch layer.kind {
        case .solid:
            guard let rgba = layer.rgba, let color = color(rgba) else { return }
            context.setFillColor(color.cgColor)
            context.fill(rect)
        case .linearGradient:
            guard let angle = layer.angleDegrees else { return }
            let ordered = CanvasAuthoredFillCompositor.interpolationStops(for: layer)
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return }
            let line = CanvasAuthoredFillCompositor.gradientLine(angleDegrees: angle, width: rect.width, height: rect.height)
            let start = CGPoint(
                x: rect.minX + line.start.x,
                y: rect.minY + line.start.y
            )
            let end = CGPoint(
                x: rect.minX + line.end.x,
                y: rect.minY + line.end.y
            )
            let needsPremultipliedColor = zip(ordered, ordered.dropFirst()).contains { a, b in
                b.position > a.position && a.rgba[3] != b.rgba[3] && Array(a.rgba.prefix(3)) != Array(b.rgba.prefix(3))
            }
            if needsPremultipliedColor {
                let info = Unmanaged.passRetained(NativeGradientFunction(stops: ordered))
                var callbacks = CGFunctionCallbacks(version: 0, evaluate: { pointer, input, output in
                    guard let pointer else { for i in 0..<4 { output[i] = 0 }; return }
                    let value = Unmanaged<NativeGradientFunction>.fromOpaque(pointer).takeUnretainedValue()
                    let rgba = CanvasAuthoredFillCompositor.gradientRGBA(orderedStops: value.stops, at: Double(input[0])) ?? [0,0,0,0]
                    for i in 0..<4 { output[i] = CGFloat(rgba[i]) }
                }, releaseInfo: { pointer in
                    if let pointer { Unmanaged<NativeGradientFunction>.fromOpaque(pointer).release() }
                })
                guard let function = CGFunction(info: info.toOpaque(), domainDimension: 1, domain: [0,1],
                    rangeDimension: 4, range: [0,1,0,1,0,1,0,1], callbacks: &callbacks) else { info.release(); return }
                guard let shading = CGShading(axialSpace: colorSpace, start: start, end: end,
                    function: function, extendStart: true, extendEnd: true) else { return }
                context.drawShading(shading)
                return
            }
            let colors = ordered.compactMap { color($0.rgba)?.cgColor }
            guard ordered.count >= 2, colors.count == ordered.count,
                  let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray,
                    locations: ordered.map { CGFloat($0.position) }) else { return }
            // SF-0508-003: normalized sampling and CSS extend the first/last
            // stop beyond the interpolation segment. Core Graphics does not
            // do so by default, leaving transparent diagonal corner wedges.
            // The existing authored-shape clip still bounds these endpoint caps.
            context.drawLinearGradient(gradient, start: start, end: end,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }
    private static func color(_ values: [Double]) -> NSColor? {
        guard values.count == 4, values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        return NSColor(srgbRed: values[0], green: values[1], blue: values[2], alpha: values[3])
    }
}

/// Core Graphics owns this immutable callback context until shading finishes.
/// Only varying-alpha/color ramps need a function; opaque ramps retain the
/// native CGGradient fast path and exact duplicate-position hard stops.
private final class NativeGradientFunction: Sendable {
    let stops: [CanvasGradientStop]
    init(stops: [CanvasGradientStop]) { self.stops = stops }
}

private struct NativeGradientRamp: NSViewRepresentable {
    let state: WorkspaceShellState
    let layer: CanonicalFillLayer
    let selectedID: GradientStopID?
    let prefix: String
    let colorRequest: UUID?
    let select: (GradientStopID) -> Void

    func makeNSView(context: Context) -> NativeGradientRampView { NativeGradientRampView(frame: .zero) }

    func updateNSView(_ view: NativeGradientRampView, context: Context) {
        view.update(state: state, layer: layer, selectedID: selectedID, prefix: prefix, select: select)
        view.handleColorRequest(colorRequest)
    }

    static func dismantleNSView(_ view: NativeGradientRampView, coordinator: ()) {
        view.tearDown()
    }
}

/// The mouse and Colors panel share one live edit, bound to the original
/// stop identity and document context for the duration of the interaction.
private final class NativeGradientRampView: NSView {
    private struct Edit {
        let owner = UUID()
        let stop: CanonicalGradientStop
        let context: ResponsiveInspectorEditContext
        var preview: CanonicalGradientStop?
    }
    private struct Pointer {
        let stopID: GradientStopID
        let start: CGPoint
        let trackWidth: CGFloat
        var moved = false
    }
    private weak var state: WorkspaceShellState?
    private var fillLayer: CanonicalFillLayer?
    private var selectedID: GradientStopID?
    private var buttons: [GradientStopID: NativeGradientStopButton] = [:]
    private var prefix = ""
    private var select: ((GradientStopID) -> Void)?
    private var pointer: Pointer?
    private var edit: Edit?
    private var handledColorRequest: UUID?
    private var subscriptions: Set<AnyCancellable> = []
    private let well = AccessibleDesignColorWell(frame: .zero)
    private lazy var panelCoordinator = NativeDesignColorWell.Coordinator { [weak self] color in
        guard let self, let edit = self.edit else { return }
        self.preview(position: edit.stop.position, color: color)
    }
    private var track: CGRect { CGRect(x: 12, y: 6, width: max(1, bounds.width - 24), height: 21) }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        well.supportsAlpha = true
        well.setAccessibilityElement(false)
        well.target = panelCoordinator
        well.action = #selector(NativeDesignColorWell.Coordinator.colorChanged(_:))
        panelCoordinator.onEnd = { [weak self] in self?.finish() }
        panelCoordinator.onCancel = { [weak self] in self?.cancelEdit() }
        addSubview(well)
        panelCoordinator.attach(well)
    }
    required init?(coder: NSCoder) { nil }

    func update(state: WorkspaceShellState, layer: CanonicalFillLayer, selectedID: GradientStopID?,
                prefix: String, select: @escaping (GradientStopID) -> Void) {
        if let edit, edit.context != state.responsiveInspectorEditContext || self.fillLayer?.id != layer.id ||
            selectedID != edit.stop.id || !layer.isEnabled {
            cancelInteraction()
        }
        if self.state !== state {
            subscriptions.removeAll()
            state.editCommitRequests.sink { [weak self] request in
                guard request.isAccepted, let self, let edit = self.edit else { return }
                if request.action == .context {
                    self.cancelInteraction()
                } else if request.requiresCleanEditors, edit.preview != nil {
                    request.reject()
                } else {
                    self.finish()
                    self.panelCoordinator.cancelPanelInteraction()
                }
            }.store(in: &subscriptions)
            state.designStyleCancellation.sink { [weak self] in self?.cancelInteraction() }
                .store(in: &subscriptions)
        }
        self.state = state; self.fillLayer = layer; self.selectedID = selectedID
        self.prefix = prefix; self.select = select
        let ids = Set(layer.stops.map(\.id))
        for id in Array(buttons.keys) where !ids.contains(id) {
            buttons.removeValue(forKey: id)?.removeFromSuperview()
        }
        for stop in layer.stops where buttons[stop.id] == nil {
            let button = NativeGradientStopButton(id: stop.id, ramp: self)
            buttons[stop.id] = button
            addSubview(button)
        }
        refresh()
    }

    private var presentedStops: [CanonicalGradientStop] {
        (fillLayer?.stops ?? []).map { stop in edit?.preview?.id == stop.id ? edit?.preview ?? stop : stop }
    }

    private func refresh() {
        let stops = presentedStops
        for (index, stop) in stops.enumerated() {
            guard let button = buttons[stop.id] else { continue }
            button.isEnabled = fillLayer?.isEnabled == true
            button.stopColor = stop.color
            button.isSelectedStop = selectedID == stop.id
            button.setAccessibilityIdentifier(prefix + ".stop." + stop.id.description)
            button.setAccessibilityLabel("Gradient stop \(index + 1)")
            button.setAccessibilityHelp("Press to open Colors. Drag to reposition. Use the stop menu to choose overlapping stops.")
            button.details = "\(DesignStyleNumberText.string(stop.position * 100)) percent, \(stop.color.hexadecimalRGBA)" +
                (button.isSelectedStop ? ", selected" : "")
            button.needsDisplay = true
        }
        needsLayout = true
        needsDisplay = true
    }

    override func accessibilityChildren() -> [Any]? {
        fillLayer?.stops.compactMap { buttons[$0.id] }
    }

    override func layout() {
        super.layout()
        // Keep the authored X coordinate even for hard stops. The stop
        // menu can reach every identity when more than two share a position.
        for (position, stops) in Dictionary(grouping: presentedStops, by: \.position) {
            let bottom = stops.first { $0.id == selectedID }?.id ?? stops[0].id
            for stop in stops {
                let centerY = stop.id == bottom ? track.maxY : track.maxY - 14
                buttons[stop.id]?.frame = CGRect(x: track.minX + position * track.width - 11,
                                                 y: centerY - 11, width: 22, height: 22)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let layer = fillLayer, let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = track
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil))
        context.clip()
        NSColor.controlBackgroundColor.setFill()
        rect.fill()
        NSColor.quaternaryLabelColor.setFill()
        for y in stride(from: 0.0, to: rect.height, by: 6) {
            for x in stride(from: 0.0, to: rect.width, by: 6) where (Int(x / 6) + Int(y / 6)).isMultiple(of: 2) {
                NSRect(x: rect.minX + x, y: rect.minY + y, width: 6, height: 6).fill()
            }
        }
        let fill = CanvasAuthoredFillLayer(id: layer.id.rawValue, kind: .linearGradient, isEnabled: true,
            rgba: nil, angleDegrees: 0, stops: presentedStops.map { .init(id: $0.id.rawValue, position: $0.position,
                rgba: [$0.color.red, $0.color.green, $0.color.blue, $0.color.alpha]) })
        NativeAuthoredFillPainter.draw(fill, in: rect, context: context)
    }

    func beginPointer(_ event: NSEvent, stopID: GradientStopID) {
        cancelInteraction()
        pointer = Pointer(stopID: stopID, start: convert(event.locationInWindow, from: nil), trackWidth: track.width)
    }

    func movePointer(_ event: NSEvent) {
        guard var tracking = pointer else { return }
        let point = convert(event.locationInWindow, from: nil)
        let delta = point.x - tracking.start.x
        if !tracking.moved {
            guard hypot(delta, point.y - tracking.start.y) >= 3 else { return }
            tracking.moved = true
            pointer = tracking
            guard begin(tracking.stopID) else { return }
        }
        guard let edit else { return }
        preview(position: min(1, max(0, edit.stop.position + delta / tracking.trackWidth)), color: edit.stop.color)
    }

    func endPointer() {
        guard let tracking = pointer else { return }
        pointer = nil
        if tracking.moved { finish() }
        else { openColors(for: tracking.stopID) }
    }

    func handleColorRequest(_ request: UUID?) {
        guard let request, handledColorRequest != request else { return }
        handledColorRequest = request
        guard let selectedID, let context = state?.responsiveInspectorEditContext else { return }
        // Wait until the SwiftUI update finishes before opening the AppKit panel.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, self.handledColorRequest == request,
                  self.selectedID == selectedID, self.state?.responsiveInspectorEditContext == context else { return }
            self.openColors(for: selectedID)
        }
    }

    func openColors(for id: GradientStopID) {
        cancelInteraction()
        guard begin(id), let edit else { return }
        let color = edit.stop.color
        panelCoordinator.isSynchronizing = true
        well.color = NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        _ = well.accessibilityPerformPress()
        panelCoordinator.isSynchronizing = false
    }

    private func begin(_ id: GradientStopID) -> Bool {
        guard let state, fillLayer?.isEnabled == true,
              let stop = fillLayer?.stops.first(where: { $0.id == id }) else { return false }
        let context = state.responsiveInspectorEditContext
        guard state.prepareForWorkspaceAction(.context), state.responsiveInspectorEditContext == context else { return false }
        edit = Edit(stop: stop, context: context)
        selectedID = id
        select?(id)
        refresh()
        return true
    }

    private func preview(position: Double, color: CanonicalSolidColor) {
        guard var edit, let layer = fillLayer, let state, state.responsiveInspectorEditContext == edit.context else { return }
        let stop = CanonicalGradientStop(id: edit.stop.id, position: position, color: color)
        if stop == edit.stop {
            state.cancelDesignStylePreview(owner: edit.owner)
            edit.preview = nil
        } else {
            guard state.previewDesignStyle(.fill(.setStop(layer.id, stop.id, position: position, color: color)),
                                           owner: edit.owner, expectedContext: edit.context) else { return }
            edit.preview = stop
        }
        self.edit = edit
        refresh()
    }

    private func finish() {
        guard let edit else { return }
        self.edit = nil
        _ = state?.finishDesignStylePreview(owner: edit.owner)
        refresh()
    }

    private func cancelEdit() {
        guard let edit else { return }
        self.edit = nil
        state?.cancelDesignStylePreview(owner: edit.owner)
        refresh()
    }

    func cancelInteraction() {
        pointer = nil
        panelCoordinator.cancelPanelInteraction()
        cancelEdit()
    }

    func tearDown() {
        cancelInteraction()
        panelCoordinator.detach()
        subscriptions.removeAll()
        handledColorRequest = nil
    }
}

private final class NativeGradientStopButton: NSButton {
    let stopID: GradientStopID
    private weak var ramp: NativeGradientRampView?
    var stopColor = CanonicalSolidColor.legacySurface
    var details = ""
    var isSelectedStop = false

    init(id: GradientStopID, ramp: NativeGradientRampView) {
        stopID = id
        self.ramp = ramp
        super.init(frame: .zero)
        isBordered = false
        focusRingType = .none
        target = self
        action = #selector(open)
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { isEnabled }
    override func accessibilityValue() -> Any? { details }

    override func becomeFirstResponder() -> Bool {
        defer { needsDisplay = true }
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        defer { needsDisplay = true }
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        ramp?.beginPointer(event, stopID: stopID)
    }
    override func mouseDragged(with event: NSEvent) { ramp?.movePointer(event) }
    override func mouseUp(with event: NSEvent) { ramp?.endPointer() }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49, 76: open()
        case 53: ramp?.cancelInteraction()
        default: super.keyDown(with: event)
        }
    }
    @objc private func open() {
        if isEnabled { ramp?.openColors(for: stopID) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let focus = window?.firstResponder === self
        let outer = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        (focus ? NSColor.keyboardFocusIndicatorColor : isSelectedStop ? NSColor.controlAccentColor : NSColor.black).setFill()
        outer.fill()
        let separator = NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3))
        NSColor.white.setFill()
        separator.fill()
        let color = NSColor(srgbRed: stopColor.red, green: stopColor.green, blue: stopColor.blue, alpha: stopColor.alpha)
        let inner = NSBezierPath(ovalIn: bounds.insetBy(dx: 4, dy: 4))
        NSColor.controlBackgroundColor.setFill()
        inner.fill()
        (isEnabled ? color : color.withAlphaComponent(stopColor.alpha * 0.5)).setFill()
        inner.fill()
    }
}

/// SF-0506-002/005/006, SF-0508-002/005/006: the slider's native tracking
/// loop owns a fixed range and one preview/commit boundary.
struct DesignStyleSlider: NSViewRepresentable {
    var minimum = 0.0
    let value: Double
    let maximum: Double
    let isEnabled: Bool
    let label: String
    let identifier: String
    let context: ResponsiveInspectorEditContext
    let begin: () -> Bool
    let preview: (Double) -> Void
    let finish: () -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(preview: preview) }
    func makeNSView(context: Context) -> TrackingDesignSlider {
        let view = TrackingDesignSlider(frame: .zero)
        view.isContinuous = true; view.sliderType = .linear
        view.minValue = minimum; view.maxValue = maximum
        return view
    }
    func updateNSView(_ view: TrackingDesignSlider, context: Context) {
        context.coordinator.preview = preview
        view.target = context.coordinator; view.action = #selector(Coordinator.changed(_:))
        view.onBegin = begin; view.onFinish = finish; view.onCancel = cancel
        view.isEnabled = isEnabled
        if view.isTrackingGesture, view.gestureContext != self.context {
            view.cancelGesture(restoring: value)
        }
        if !view.isTrackingGesture {
            view.minValue = minimum
            view.maxValue = max(minimum + 0.0001, maximum)
            view.doubleValue = value
            view.representedContext = self.context
        }
        view.setAccessibilityIdentifier(identifier); view.setAccessibilityLabel(label)
        view.setAccessibilityHelp("Drag to preview. Release commits one undo step. Escape restores the starting value. Arrow keys adjust by one; Shift adjusts by ten.")
    }
    static func dismantleNSView(_ view: TrackingDesignSlider, coordinator: Coordinator) {
        view.cancelGesture(); view.detachMonitor()
        view.target = nil; view.action = nil
        view.onBegin = nil; view.onFinish = nil; view.onCancel = nil
        coordinator.preview = { _ in }
    }
    @MainActor final class Coordinator: NSObject {
        var preview: (Double) -> Void
        init(preview: @escaping (Double) -> Void) { self.preview = preview }
        @objc func changed(_ sender: TrackingDesignSlider) {
            guard !sender.gestureCancelled else { sender.restoreCancelledValue(); return }
            let value = (sender.doubleValue * 10).rounded() / 10
            sender.doubleValue = value
            preview(value)
        }
    }
}

final class TrackingDesignSlider: NSSlider {
    var representedContext: ResponsiveInspectorEditContext?
    private(set) var gestureContext: ResponsiveInspectorEditContext?
    private(set) var isTrackingGesture = false
    private(set) var gestureCancelled = false
    var onBegin: (() -> Bool)?
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?
    private var startingValue = 0.0
    private var isMouseGesture = false
    private var keyMonitor: Any?

    override var acceptsFirstResponder: Bool { isEnabled }

    override func mouseDown(with event: NSEvent) {
        guard beginGesture(mouse: true) else { return }
        window?.makeFirstResponder(self)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isTrackingGesture, event.keyCode == 53 else { return event }
            self.cancelGesture(); return nil
        }
        super.mouseDown(with: event)
        finishGesture()
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, isTrackingGesture {
            cancelGesture(); if !isMouseGesture { finishGesture() }; return
        }
        let direction: Double
        switch event.keyCode {
        case 123, 125: direction = -1
        case 124, 126: direction = 1
        default: super.keyDown(with: event); return
        }
        if !isTrackingGesture, !beginGesture(mouse: false) { return }
        guard !gestureCancelled else { return }
        adjust(by: direction * (event.modifierFlags.contains(.shift) ? 10 : 1))
    }
    override func keyUp(with event: NSEvent) {
        super.keyUp(with: event)
        if isTrackingGesture, !isMouseGesture { finishGesture() }
    }
    override func resignFirstResponder() -> Bool {
        if isTrackingGesture, !isMouseGesture { finishGesture() }
        return super.resignFirstResponder()
    }
    override func accessibilityPerformIncrement() -> Bool { accessibilityAdjust(by: 1) }
    override func accessibilityPerformDecrement() -> Bool { accessibilityAdjust(by: -1) }

    func cancelGesture(restoring value: Double? = nil) {
        guard isTrackingGesture, !gestureCancelled else { return }
        gestureCancelled = true
        if let value { startingValue = value }
        doubleValue = startingValue
        onCancel?()
    }
    func restoreCancelledValue() { doubleValue = startingValue }
    func detachMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
    private func beginGesture(mouse: Bool) -> Bool {
        guard isEnabled, onBegin?() != false else { return false }
        startingValue = doubleValue; gestureContext = representedContext
        gestureCancelled = false; isTrackingGesture = true; isMouseGesture = mouse
        return true
    }
    private func finishGesture() {
        guard isTrackingGesture else { return }
        let shouldCommit = !gestureCancelled
        isTrackingGesture = false; isMouseGesture = false; detachMonitor()
        if shouldCommit { onFinish?() }
    }
    private func adjust(by delta: Double) {
        let next = min(maxValue, max(minValue, doubleValue + delta))
        guard next != doubleValue else { return }
        doubleValue = next; _ = sendAction(action, to: target)
        NSAccessibility.post(element: self, notification: .valueChanged)
    }
    private func accessibilityAdjust(by delta: Double) -> Bool {
        guard beginGesture(mouse: false) else { return false }
        let old = doubleValue; adjust(by: delta); finishGesture()
        return old != doubleValue
    }
}


/// Native device Preview and canvas tiles share the same gradient sampling.
/// This is an authored surface, not a midpoint-color approximation.
struct NativeAuthoredFillSurface: NSViewRepresentable {
    let layers: [CanvasAuthoredFillLayer]
    let radius: Double
    func makeNSView(context: Context) -> NativeAuthoredFillSurfaceView { .init() }
    func updateNSView(_ view: NativeAuthoredFillSurfaceView, context: Context) {
        view.fills = layers; view.radius = radius; view.needsDisplay = true
    }
}

final class NativeAuthoredFillSurfaceView: NSView {
    var fills: [CanvasAuthoredFillLayer] = []
    var radius = 0.0
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState(); defer { context.restoreGState() }
        let corner = min(radius, min(bounds.width, bounds.height) / 2)
        context.addPath(CGPath(roundedRect: bounds, cornerWidth: corner, cornerHeight: corner, transform: nil))
        context.clip()
        for layer in fills where layer.isEnabled { NativeAuthoredFillPainter.draw(layer, in: bounds, context: context) }
    }
}

/// Numeric drafts keep authored precision; pointer gestures deliberately step
/// by tenths. Display formatting never rewrites a canonical value on inspection.
enum DesignStyleNumberText {
    static func string(_ value: Double) -> String {
        String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
