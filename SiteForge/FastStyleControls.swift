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
                DesignStyleSlider(value: displayed.alpha * 100, maximum: 100, isEnabled: isEnabled,
                    label: label + " alpha", identifier: identifier + ".alphaSlider", context: context,
                    begin: { validation == nil },
                    preview: { value in update(.init(red: displayed.red, green: displayed.green,
                        blue: displayed.blue, alpha: value / 100), context: context) },
                    finish: { finish() }, cancel: { cancel() })
                    .frame(minWidth: 50)
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
    @State private var activeID: FillLayerID?
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
    @State private var draggedPosition: Double?
    @State private var dragOwner = UUID()
    @State private var dragging = false
    @State private var dragCancelled = false
    @State private var dragContext: ResponsiveInspectorEditContext?
    private var stop: CanonicalGradientStop? { layer.stops.first { $0.id == selectedID } ?? layer.stops.first }
    private var prefix: String { "inspector.design.ramp." + layer.id.description }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                let width = max(1, geometry.size.width - 12)
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(.quaternary).frame(height: 22)
                    NativeGradientRamp(stops: layer.stops.map { candidate in
                        .init(id: candidate.id, position: candidate.id == selectedID ? draggedPosition ?? candidate.position : candidate.position, color: candidate.color)
                    }).frame(height: 22)
                    ForEach(layer.stops, id: \.id) { candidate in
                        let position = candidate.id == selectedID ? draggedPosition ?? candidate.position : candidate.position
                        Button { if state.prepareForWorkspaceAction(.context) { selectedID = candidate.id } } label: {
                            Image(systemName: "diamond.fill")
                                .foregroundStyle(candidate.id == stop?.id ? Color.accentColor : Color.primary)
                                .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
                                .frame(width: 18, height: 20)
                        }.buttonStyle(.plain)
                        .offset(x: position * width - 3, y: 17)
                        .accessibilityLabel("Gradient stop \(layer.stops.firstIndex(where: { $0.id == candidate.id })! + 1)")
                        .accessibilityValue(String(format: "%.1f percent", position * 100))
                        .accessibilityIdentifier(prefix + ".stop." + candidate.id.description)
                        .simultaneousGesture(DragGesture(minimumDistance: 2).onChanged { value in
                            if !dragging { dragging = true; dragCancelled = false; dragContext = state.responsiveInspectorEditContext }
                            guard !dragCancelled else { return }
                            selectedID = candidate.id
                            let next = min(1, max(0, candidate.position + value.translation.width / width))
                            if state.previewDesignStyle(.fill(.setStop(layer.id, candidate.id, position: next, color: candidate.color)), owner: dragOwner, expectedContext: dragContext) { draggedPosition = next }
                        }.onEnded { _ in
                            if !dragCancelled { _ = state.finishDesignStylePreview(owner: dragOwner) }
                            draggedPosition = nil; dragContext = nil; dragging = false; dragCancelled = false
                        })
                    }
                }.padding(.horizontal, 6)
            }.frame(height: 40).accessibilityElement(children: .contain).accessibilityLabel("Gradient ramp")
            if let stop {
                DesignColorEditor(state: state, color: stop.color, isEnabled: layer.isEnabled,
                    label: "Selected gradient stop", identifier: prefix + ".color",
                    edit: { .fill(.setStop(layer.id, stop.id, position: stop.position, color: $0)) })
                    .id(prefix + stop.id.description)
                HStack {
                    Text("Position").font(.caption)
                    GradientNumberField(state: state, value: stop.position * 100, label: "Selected stop position", identifier: prefix + ".position", percentage: true) { value in
                        state.commitDesignFillLayer(.setStop(layer.id, stop.id, position: value / 100, color: stop.color), operation: "gradient stop position", provenance: .keyboard)
                    }
                    Text("%").font(.caption)
                    Spacer(minLength: 0)
                    Button("Add Stop") { if let newStop = GradientAuthoringInsertion.stop(in: layer) {
                        selectedID = newStop.id
                        _ = state.commitDesignFillLayer(.addStop(layer.id, newStop, at: layer.stops.count), operation: "add gradient stop")
                    }}.accessibilityIdentifier(prefix + ".addStop")
                }
            }
            HStack {
                Text("Direction").font(.caption)
                Image(systemName: "arrow.right").rotationEffect(.degrees(layer.normalizedAngleDegrees ?? 0))
                    .frame(width: 24, height: 24).accessibilityHidden(true)
                GradientNumberField(state: state, value: layer.normalizedAngleDegrees ?? 0, label: "Gradient direction", identifier: prefix + ".angle", percentage: false) { value in
                    state.commitDesignFillLayer(.setGradientAngle(layer.id, value), operation: "gradient direction", provenance: .keyboard)
                }
                Text("°").font(.caption)
            }
        }
        .disabled(!layer.isEnabled)
        .onExitCommand { cancelDrag() }
        .onDisappear { cancelDrag() }
        .onChange(of: state.responsiveInspectorEditContext) { _, _ in cancelDrag() }
    }
    private func cancelDrag() {
        state.cancelDesignStylePreview(owner: dragOwner); draggedPosition = nil; dragContext = nil
        if dragging { dragCancelled = true }
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
    let stops: [CanonicalGradientStop]
    func makeNSView(context: Context) -> NativeGradientRampView { NativeGradientRampView() }
    func updateNSView(_ view: NativeGradientRampView, context: Context) {
        view.fill = .init(id: view.layerID, kind: .linearGradient, isEnabled: true, rgba: nil, angleDegrees: 0,
            stops: stops.map { .init(id: $0.id.rawValue, position: $0.position,
                rgba: [$0.color.red, $0.color.green, $0.color.blue, $0.color.alpha]) })
        view.needsDisplay = true
    }
}

private final class NativeGradientRampView: NSView {
    let layerID = UUID()
    var fill: CanvasAuthoredFillLayer?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState(); defer { context.restoreGState() }
        context.addPath(CGPath(roundedRect: bounds, cornerWidth: 4, cornerHeight: 4, transform: nil)); context.clip()
        NSColor.controlBackgroundColor.setFill(); bounds.fill()
        NSColor.quaternaryLabelColor.setFill()
        for y in stride(from: 0.0, to: bounds.height, by: 6) {
            for x in stride(from: 0.0, to: bounds.width, by: 6) where (Int(x / 6) + Int(y / 6)).isMultiple(of: 2) {
                NSRect(x: x, y: y, width: 6, height: 6).fill()
            }
        }
        if let fill { NativeAuthoredFillPainter.draw(fill, in: bounds, context: context) }
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

